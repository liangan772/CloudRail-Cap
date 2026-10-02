# frozen_string_literal: true

module DiscourseCap
  # Talks to a self-hosted Cap standalone server.
  #
  # Cap exposes a reCAPTCHA-compatible endpoint:
  #
  #   POST {base}/{site_key}/siteverify
  #   { "secret": "<secret_key>", "response": "<token>" }
  #   -> { "success": true }
  #
  # Tokens are single-use, so every token must be redeemed exactly once.
  module Verify
    class Failure < StandardError
      attr_reader :reason

      def initialize(reason)
        @reason = reason
        super(reason.to_s)
      end
    end

    class << self
      # Raises DiscourseCap::Verify::Failure when verification should block the
      # request. Returns true when the submission may proceed.
      #
      # `actor` is the current_user for the request (may be nil). Every value
      # needed is passed in explicitly so this stays safe under concurrency.
      def enforce!(token:, remote_ip:, context:, actor: nil)
        return true unless SiteSetting.cap_verification_enabled
        return true if bypass_for?(actor)

        token = token.to_s.strip
        raise Failure.new(:missing_token) if token.blank?
        raise Failure.new(:token_too_long) if token.length > 4096
        raise Failure.new(:not_configured) unless Config.configured?

        unless valid_token?(token)
          throttle!(context, remote_ip)
          log_failure(remote_ip, context, "invalid")
          raise Failure.new(:invalid_token)
        end

        true
      end

      # Probes the instance with a deliberately invalid token. A well-formed
      # `{ "success": false }` response proves the server is reachable and the
      # secret was accepted, so `success: false` is the healthy outcome here.
      def test_connection
        unless Config.configured?
          return({ success: false, error: I18n.t("cap_verification.admin.not_configured") })
        end

        parsed, status = post_to_cap("__connection_probe__")

        if status.is_a?(Net::HTTPSuccess) && parsed.is_a?(Hash) && parsed.key?("success")
          { success: true, message: I18n.t("cap_verification.admin.connection_ok") }
        else
          { success: false, error: "HTTP #{status.code}" }
        end
      rescue StandardError => e
        { success: false, error: "#{e.class}: #{e.message}" }
      end

      def valid_token?(token)
        parsed, status = post_to_cap(token)
        return false unless status.is_a?(Net::HTTPSuccess)

        parsed.is_a?(Hash) && parsed["success"] == true
      rescue StandardError => e
        Rails.logger.warn("[cap-verification] verify failed: #{e.class}: #{e.message}")
        false
      end

      private

      def post_to_cap(token)
        uri = URI.parse(verify_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = SiteSetting.cap_verification_timeout_seconds
        http.read_timeout = SiteSetting.cap_verification_timeout_seconds

        request = Net::HTTP::Post.new(uri.request_uri)
        request["Content-Type"] = "application/json"
        request.body =
          JSON.generate(
            secret: SiteSetting.cap_verification_secret_key,
            response: token,
          )

        response = http.request(request)
        parsed = begin
          JSON.parse(response.body)
        rescue JSON::ParserError
          nil
        end

        [parsed, response]
      end

      def verify_url
        base = SiteSetting.cap_verification_instance_url.to_s.strip
        base = "https://#{base}" unless base.match?(%r{\Ahttps?://}i)
        "#{base.chomp("/")}/#{SiteSetting.cap_verification_site_key}/siteverify"
      end

      # Staff and users at or above the configured trust level never see the
      # challenge. This also means an authenticated session cannot be used to
      # bypass signup protection, because signup always has actor == nil.
      def bypass_for?(actor)
        return false if actor.blank?
        return true if SiteSetting.cap_verification_skip_for_staff && actor.staff?

        min_tl = SiteSetting.cap_verification_min_trust_level.to_i
        min_tl.positive? && actor.trust_level.to_i >= min_tl
      end

      def throttle!(context, remote_ip)
        RateLimiter.new(
          nil,
          "cap-verification-#{context}",
          SiteSetting.cap_verification_max_attempts,
          60,
        ).performed!
      rescue RateLimiter::LimitExceeded
        raise
      rescue StandardError => e
        Rails.logger.warn("[cap-verification] throttle failed: #{e.message}")
      end

      def log_failure(remote_ip, context, reason)
        DiscourseCap::VerificationLog.create(
          remote_ip: remote_ip.to_s,
          context: context.to_s,
          reason: reason,
          created_at: Time.zone.now,
        )
      rescue StandardError => e
        Rails.logger.warn("[cap-verification] log failure: #{e.message}")
      end
    end
  end
end

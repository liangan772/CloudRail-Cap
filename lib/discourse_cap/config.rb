# frozen_string_literal: true

module DiscourseCap
  # Single source of truth for "is Cap usable right now?" plus the payload the
  # client widget needs. Keeping this in one place avoids the classic mistake of
  # having the browser render a checkbox while the server silently accepts every
  # submission.
  module Config
    class << self
      # Only enables the widget when the server can actually verify what the
      # widget produces. Never show a checkbox we cannot check.
      def enabled?
        SiteSetting.cap_verification_enabled && configured?
      end

      def configured?
        SiteSetting.cap_verification_instance_url.present? &&
          SiteSetting.cap_verification_site_key.present? &&
          SiteSetting.cap_verification_secret_key.present?
      end

      # Sent to the client through the site serializer. The secret key is
      # deliberately absent.
      def client_payload
        {
          enabled: enabled?,
          protect_signup: SiteSetting.cap_verification_protect_signup,
          protect_login: SiteSetting.cap_verification_protect_login,
          instance_url: public_instance_url,
          site_key: SiteSetting.cap_verification_site_key,
          widget_theme: SiteSetting.cap_verification_widget_theme,
          script_url: SiteSetting.cap_verification_widget_script_url,
        }
      end

      def public_instance_url
        url = SiteSetting.cap_verification_instance_url.to_s.strip
        return "" if url.blank?

        url = "https://#{url}" unless url.match?(%r{\Ahttps?://}i)
        url.chomp("/")
      end
    end
  end
end

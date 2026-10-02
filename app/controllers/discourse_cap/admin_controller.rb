# frozen_string_literal: true

module DiscourseCap
  # Admin settings screen for the plugin. Mounted at
  # /admin/plugins/cap-verification and rendered by a .gjs template.
  #
  # Site settings can also be edited at /admin/site_settings (under "Plugins"),
  # but this screen gives a focused, self-documenting setup flow.
  class AdminController < ::Admin::AdminController
    def index
      render_json_dump(settings_payload)
    end

    def update
      params.require(:cap_verification)

      updates = {
        cap_verification_enabled: boolean_param(:enabled),
        cap_verification_instance_url: string_param(:instance_url),
        cap_verification_site_key: string_param(:site_key),
        cap_verification_secret_key: string_param(:secret_key),
        cap_verification_widget_theme: string_param(:widget_theme),
        cap_verification_widget_script_url: string_param(:widget_script_url),
        cap_verification_protect_signup: boolean_param(:protect_signup),
        cap_verification_protect_login: boolean_param(:protect_login),
        cap_verification_skip_for_staff: boolean_param(:skip_for_staff),
        cap_verification_min_trust_level: integer_param(:min_trust_level),
        cap_verification_max_attempts: integer_param(:max_attempts),
        cap_verification_timeout_seconds: integer_param(:timeout_seconds),
      }.compact

      updates.each do |key, value|
        next if value.nil?
        SiteSetting.send("#{key}=", value)
      end

      render_json_dump(settings_payload)
    rescue Discourse::InvalidParameters => e
      render_json_error(e.message)
    end

    def test
      render_json_dump(DiscourseCap::Verify.test_connection)
    end

    private

    def settings_payload
      {
        enabled: SiteSetting.cap_verification_enabled,
        configured: DiscourseCap::Config.configured?,
        running: DiscourseCap::Config.enabled?,
        instance_url: SiteSetting.cap_verification_instance_url,
        site_key: SiteSetting.cap_verification_site_key,
        secret_key_set: SiteSetting.cap_verification_secret_key.present?,
        widget_theme: SiteSetting.cap_verification_widget_theme,
        widget_script_url: SiteSetting.cap_verification_widget_script_url,
        protect_signup: SiteSetting.cap_verification_protect_signup,
        protect_login: SiteSetting.cap_verification_protect_login,
        skip_for_staff: SiteSetting.cap_verification_skip_for_staff,
        min_trust_level: SiteSetting.cap_verification_min_trust_level,
        max_attempts: SiteSetting.cap_verification_max_attempts,
        timeout_seconds: SiteSetting.cap_verification_timeout_seconds,
        failed_last_24h:
          (DiscourseCap::VerificationLog.recent_count rescue nil),
      }
    end

    def boolean_param(key)
      return nil unless params[:cap_verification].key?(key)
      ActiveModel::Type::Boolean.new.cast(params[:cap_verification][key])
    end

    def string_param(key)
      value = params[:cap_verification][key]
      value.nil? ? nil : value.to_s.strip
    end

    def integer_param(key)
      value = params[:cap_verification][key]
      return nil if value.nil?
      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end
  end
end

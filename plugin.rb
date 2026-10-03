# frozen_string_literal: true

# name: CloudRail-Cap
# about: Self-hosted human verification for Discourse using Cap (a proof-of-work CAPTCHA). Adds a Cap checkbox to signup and login, verifies tokens server-side, and ships an admin settings screen.
# version: 1.0.0
# authors: WorkBuddy AI
# url: https://github.com/liangan772/CloudRail-Cap
# required_version: 3.3.0
# transpile_js: true

enabled_site_setting :cap_verification_enabled

register_asset "stylesheets/cap-verification.scss"
register_svg_icon "shield-halved"

module ::DiscourseCap
  # Must equal the plugin directory name, which is what the git clone in
  # containers/app.yml produces. Discourse warns and misregisters the plugin
  # in /admin/plugins when this and the directory disagree.
  PLUGIN_NAME = "CloudRail-Cap"
end

# `lib/` is not autoloaded, so these are required explicitly. Files under
# `app/` (the model, the controller and the serializer concern used below) are
# owned by Zeitwerk and must NOT be require_relative'd - doing so raises
# Zeitwerk::NameError during boot.
require_relative "lib/discourse_cap/config"
require_relative "lib/discourse_cap/verify"

after_initialize do
  # ---------------------------------------------------------------------
  # Server-side enforcement
  # ---------------------------------------------------------------------
  #
  # `UsersController#create` handles signup, `SessionController#create`
  # handles local login. Both accept form params, so the token arrives as
  # `params[:cap_token]` (injected by the <cap-widget> hidden field, or by
  # our connector component in the JS flow).
  #
  add_to_class(:users_controller, :create) do
    if SiteSetting.cap_verification_enabled && SiteSetting.cap_verification_protect_signup
      begin
        DiscourseCap::Verify.enforce!(
          token: params[:cap_token],
          remote_ip: request.remote_ip,
          context: "signup",
          actor: current_user,
        )
      rescue DiscourseCap::Verify::Failure => e
        return render_json_error(I18n.t("cap_verification.errors.#{e.reason}"), status: 403)
      rescue RateLimiter::LimitExceeded
        return render_json_error(I18n.t("cap_verification.errors.too_many_attempts"), status: 429)
      end
    end
    super()
  end

  add_to_class(:session_controller, :create) do
    if SiteSetting.cap_verification_enabled && SiteSetting.cap_verification_protect_login
      begin
        DiscourseCap::Verify.enforce!(
          token: params[:cap_token],
          remote_ip: request.remote_ip,
          context: "login",
          actor: current_user,
        )
      rescue DiscourseCap::Verify::Failure => e
        return render_json_error(I18n.t("cap_verification.errors.#{e.reason}"), status: 403)
      rescue RateLimiter::LimitExceeded
        return render_json_error(I18n.t("cap_verification.errors.too_many_attempts"), status: 429)
      end
    end
    super()
  end

  # Expose the plugin's public configuration to the client so the widget
  # component knows which instance + site key to talk to.
  add_to_serializer(:site, :cap_verification) do
    DiscourseCap::Config.client_payload
  end

  # ---------------------------------------------------------------------
  # Admin configuration screen
  # ---------------------------------------------------------------------
  #
  # Two things matter here, and both were wrong before.
  #
  # 1. `use_new_show_route: true` — the modern plugin show page. This makes
  #    full_location "adminPlugins.show", a CORE route, so the link in the
  #    plugin list always resolves. With `false` the location becomes
  #    "adminPlugins.<slug>", which only exists if the plugin mounts it, and
  #    when it does not you get core's `admin.plugins.broken_route` alert:
  #      Unable to configure link to '...'. Ensure ad-blockers are disabled...
  #    No plugin in the Discourse repo still uses `false`.
  #
  # 2. The location MUST be the plugin's name (`# name:`, which equals the
  #    installed directory name). Admin::PluginsController#show resolves the
  #    page with:
  #        Discourse.plugins_by_name[params[:plugin_id]]
  #    and `plugins_by_name` is keyed by plugin name, not by an arbitrary slug.
  #    Anything else 404s on /admin/plugins/<location>.json.
  #
  # The URL is therefore /admin/plugins/CloudRail-Cap, and the plugin's own
  # page lives at /admin/plugins/CloudRail-Cap/verification (see the route map
  # in assets/javascripts/discourse/cap-verification-route-map.js).
  add_admin_route("cap_verification.admin.title", "CloudRail-Cap", {
    use_new_show_route: true,
  })

  # The settings API. Deliberately NOT under /admin/plugins/<plugin_id>, so it
  # can never be shadowed by (or shadow) core's /admin/plugins/:plugin_id route.
  Discourse::Application.routes.append do
    scope "/cap-verification", constraints: StaffConstraint.new do
      get "/settings" => "discourse_cap/admin#index"
      put "/settings" => "discourse_cap/admin#update"
      post "/test" => "discourse_cap/admin#test"
    end
  end
end

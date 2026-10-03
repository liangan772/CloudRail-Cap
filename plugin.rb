# frozen_string_literal: true

# name: cloudrail-cap
# about: Self-hosted human verification for Discourse using Cap (a proof-of-work CAPTCHA). Adds a Cap checkbox to signup and login, verifies tokens server-side, and ships an admin settings screen.
# version: 1.0.0
# authors: WorkBuddy AI
# url: https://github.com/liangan772/CloudRail-Cap
# required_version: 3.3.0
# transpile_js: true
#
# NAME AND DIRECTORY MUST BOTH BE LOWERCASE.
#
# A plugin's stylesheet target is its DIRECTORY name, and core serves it through
# a route constrained to lowercase:
#
#   # config/routes.rb
#   get "stylesheets/:name" => "stylesheets#show",
#       constraints: { name: /[-a-z0-9_]+/, format: "css" }
#
# The browser requests `/stylesheets/<directory>_<digest>.css`. With a
# capitalized directory that request never matches the route, falls through to
# the 404 page, and comes back as `text/html` — which the browser refuses:
#
#   Refused to apply style ... MIME type ('text/html') is not a supported
#   stylesheet MIME type, and strict MIME checking is enabled.
#
# The JS bundle is unaffected (different route), so the symptom is a plugin
# whose JavaScript loads while its CSS silently 404s. Every plugin in the
# Discourse repo uses a lowercase directory for this reason.

enabled_site_setting :cap_verification_enabled

register_asset "stylesheets/cap-verification.scss"
register_svg_icon "shield-halved"

module ::DiscourseCap
  # Must equal the plugin directory name, which is what the git clone in
  # containers/app.yml produces. Keep both lowercase — see the note at the top
  # of this file: an uppercase directory breaks the stylesheet route.
  PLUGIN_NAME = "cloudrail-cap"
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
  # The token cannot ride along with the signup/login request. Discourse builds
  # both payloads explicitly in JS:
  #
  #   // frontend/discourse/app/models/user.js
  #   const data = { name, email, password, username, ... };
  #   ajax(userPath(), { data, type: "POST" });
  #
  # so a hidden form field is never submitted. There is also no plugin hook for
  # the login flow: BEHAVIOR_TRANSFORMERS has "create-account" but nothing for
  # login, and plugin-api exposes no login/session API at all.
  #
  # So verification happens when the visitor SOLVES the challenge. The widget
  # POSTs the token to /cap-verification/verify, which redeems it against Cap
  # and records the result in the Rails session. Signup and login then just
  # check that flag. Discourse's own captcha plugin verifies out-of-band and
  # keeps the result server-side in the same way.
  #
  add_to_class(:users_controller, :create) do
    if SiteSetting.cap_verification_enabled && SiteSetting.cap_verification_protect_signup
      begin
        DiscourseCap::Verify.enforce_session!(
          session: session,
          remote_ip: request.remote_ip,
          context: "signup",
          actor: current_user,
        )
      rescue DiscourseCap::Verify::Failure => e
        return render_json_error(I18n.t("cap_verification.errors.#{e.reason}"), status: 403)
      end
    end
    super()
  end

  add_to_class(:session_controller, :create) do
    if SiteSetting.cap_verification_enabled && SiteSetting.cap_verification_protect_login
      begin
        DiscourseCap::Verify.enforce_session!(
          session: session,
          remote_ip: request.remote_ip,
          context: "login",
          actor: current_user,
        )
      rescue DiscourseCap::Verify::Failure => e
        return render_json_error(I18n.t("cap_verification.errors.#{e.reason}"), status: 403)
      end
    end
    super()
  end

  # Expose the plugin's public configuration to the client so the widget
  # component knows which instance + site key to talk to. This lands on the
  # `site` model (read it as `site.cap_verification`), NOT on `siteSettings` -
  # `siteSettings` only carries values from config/settings.yml marked
  # `client: true`.
  add_to_serializer(:site, :cap_verification) do
    DiscourseCap::Config.client_payload
  end

  # Reachable while signed out (signup and login are anonymous flows), so this
  # is deliberately not behind StaffConstraint.
  Discourse::Application.routes.append do
    post "/cap-verification/verify" => "discourse_cap/verification#verify"
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
  # The URL is therefore /admin/plugins/cloudrail-cap, and the plugin's own
  # page lives at /admin/plugins/cloudrail-cap/verification (see the route map
  # in assets/javascripts/discourse/cap-verification-route-map.js).
  add_admin_route("cap_verification.admin.title", PLUGIN_NAME, {
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

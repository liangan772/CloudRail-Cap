# frozen_string_literal: true

# name: discourse-cap-verification
# about: Self-hosted human verification for Discourse using Cap (a proof-of-work CAPTCHA). Adds a Cap checkbox to signup and login, verifies tokens server-side, and ships an admin settings screen.
# version: 1.0.0
# authors: WorkBuddy AI
# url: https://github.com/trycap/cap
# required_version: 3.3.0
# transpile_js: true

enabled_site_setting :cap_verification_enabled

register_asset "stylesheets/cap-verification.scss"
register_svg_icon "shield-halved"

after_initialize do
  module ::DiscourseCap
    PLUGIN_NAME = "discourse-cap-verification"
  end

  require_relative "app/services/discourse_cap/config"
  require_relative "app/services/discourse_cap/verify"
  require_relative "app/models/discourse_cap/verification_log"
  require_relative "app/controllers/discourse_cap/admin_controller"

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
  # `use_new_show_route: false` maps the slug onto the `adminPlugins.<slug>`
  # route, i.e. /admin/plugins/cap-verification. Discourse resolves that route
  # to `assets/javascripts/discourse/templates/admin/plugins/<slug>.gjs`, with
  # `routes/admin-plugins-<slug>.js` supplying the model.
  add_admin_route("cap_verification.admin.title", "cap-verification", {
    use_new_show_route: false,
  })

  Discourse::Application.routes.append do
    scope "/admin/plugins/cap-verification", constraints: StaffConstraint.new do
      get "/" => "discourse_cap/admin#index"
      put "/" => "discourse_cap/admin#update"
      post "/test" => "discourse_cap/admin#test"
    end
  end
end

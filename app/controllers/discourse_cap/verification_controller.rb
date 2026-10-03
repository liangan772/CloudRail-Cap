# frozen_string_literal: true

module DiscourseCap
  # Public endpoint the widget calls once the visitor has solved the challenge.
  #
  # It must be reachable while signed out, because it is part of both signup and
  # login, so it is NOT an AdminController and NOT behind StaffConstraint. It
  # does exactly one thing: redeem a token against Cap and record the result in
  # the visitor's session. `Verify.redeem!` does the rate limiting and the audit
  # logging, and the secret key never leaves the server.
  #
  # The token cannot be sent with the signup/login request itself - Discourse
  # builds those payloads explicitly in JS, so a hidden form field is never
  # submitted, and there is no plugin hook for the login flow at all.
  #
  # Shaped after plugins/discourse-captcha's CaptchaController, which is the
  # core-blessed way to expose an anonymous verification endpoint. The
  # `redirect_to_login_if_required` skip is essential: without it an anonymous
  # POST is bounced to the login page.
  class VerificationController < ::ApplicationController
    requires_plugin PLUGIN_NAME

    skip_before_action :redirect_to_login_if_required

    def verify
      DiscourseCap::Verify.redeem!(
        token: params[:token],
        session: session,
        remote_ip: request.remote_ip,
        context: params[:context].presence || "signup",
      )

      render json: { success: true }
    rescue DiscourseCap::Verify::Failure => e
      render json: {
               success: false,
               error: I18n.t("cap_verification.errors.#{e.reason}"),
             }
    rescue RateLimiter::LimitExceeded
      render json: {
               success: false,
               error: I18n.t("cap_verification.errors.too_many_attempts"),
             }
    end
  end
end

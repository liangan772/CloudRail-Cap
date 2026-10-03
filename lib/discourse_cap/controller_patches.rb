# frozen_string_literal: true

module DiscourseCap
  # Shared by both controller patches below.
  #
  # Deliberately NOT `add_to_class`. See the long comment in plugin.rb for the
  # proof, but the short version: `add_to_class` renames the block to
  # `create_without_enable_check`, so `super` inside it hunts for
  # `create_without_enable_check` in the superclass, never finds it, and raises.
  #
  #   NoMethodError: super: no superclass method
  #                  `create_without_enable_check' for an instance of
  #                  UsersController
  #
  # A `before_action` needs no `super` at all, which is exactly why core's own
  # captcha plugin uses one.
  module ControllerPatch
    extend ActiveSupport::Concern

    private

    # Returns nil when the request may proceed, or a Symbol naming the reason it
    # may not. Never raises, so the caller stays readable.
    def cap_verification_failure(context)
      return nil unless SiteSetting.cap_verification_enabled

      DiscourseCap::Verify.enforce_session!(
        session: session,
        remote_ip: request.remote_ip,
        context: context,
        actor: current_user,
      )

      nil
    rescue DiscourseCap::Verify::Failure => e
      e.reason
    rescue RateLimiter::LimitExceeded
      :too_many_attempts
    end

    def reject_unverified_cap(reason)
      status = reason == :too_many_attempts ? 429 : 403

      render_json_error(I18n.t("cap_verification.errors.#{reason}"), status: status)
    end
  end

  # Signup. `POST /u` -> UsersController#create.
  #
  # `include`, not `prepend`: we only add a filter, we never replace the action,
  # so core's signup path runs completely untouched once verification passes.
  module UsersControllerPatch
    extend ActiveSupport::Concern
    include ControllerPatch

    included { before_action :check_cap_verification, only: [:create] }

    private

    def check_cap_verification
      return if !SiteSetting.cap_verification_protect_signup

      reason = cap_verification_failure("signup")
      reject_unverified_cap(reason) if reason
    end
  end

  # Password login. `POST /session` -> SessionController#create.
  #
  # Only `create` is gated. `create_login_code`, the 2FA branches and the
  # signup-token flow all keep working, because those are separate actions and
  # `only: [:create]` does not touch them.
  module SessionControllerPatch
    extend ActiveSupport::Concern
    include ControllerPatch

    included { before_action :check_cap_verification, only: [:create] }

    private

    def check_cap_verification
      return if !SiteSetting.cap_verification_protect_login

      reason = cap_verification_failure("login")
      reject_unverified_cap(reason) if reason
    end
  end
end

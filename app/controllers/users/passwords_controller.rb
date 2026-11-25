# frozen_string_literal: true

module Users
  # Password reset. Devise sends anyone who is already signed in away from the
  # reset form (straight to the feed), but the reset link often opens in the
  # app or a browser where the person is still signed in. A valid reset link
  # wins: sign them out and show the form.
  class PasswordsController < Devise::PasswordsController
    include AuthRateLimiting
    include SignInChecks

    prepend_before_action :sign_out_for_reset_link, only: :edit
    throttle_auth only: :create, per_ip: 5, per_email: 3, within: 15.minutes
    before_action :verify_turnstile, only: :create

    # Opening the reset link proves they read this inbox, so the address
    # counts as verified.
    def update
      request.env[AccountDevices::SIGN_IN_OPTIONS] = { method: "password_reset" }
      super do |resource|
        EmailVerification.verified!(resource, request: request) if resource.persisted? && resource.errors.empty?
      end
    end

    protected

    # With two-step login on, a new password alone doesn't sign in: the
    # authenticator code is still asked for (unless this device is trusted).
    def sign_in_after_reset_password?
      super && !two_step_needed?
    end

    def after_resetting_password_path_for(resource)
      return super unless resource_class.sign_in_after_reset_password && two_step_needed?

      begin_sign_in_check(resource, method: "password_reset") || new_session_path(resource_name)
    end

    def two_step_needed?
      resource.persisted? && resource.two_factor_enabled? && !AccountDevices.trusted?(resource, request)
    end

    private

    # Password-reset emails can be abused to spam people; when Turnstile is on
    # the reset form carries the challenge too.
    def verify_turnstile
      return unless SignupGuard.turnstile_enabled?
      return if SignupGuard.turnstile_passed?(params["cf-turnstile-response"], request.remote_ip)

      SignupGuard.record_block!("turnstile", where: "password reset", remote_ip: request.remote_ip,
                                             email: nested_param(:user, :email))
      self.resource = resource_class.new(email: nested_param(:user, :email))
      resource.errors.add(:base, "Please complete the check below and try again.")
      render :new, status: :unprocessable_entity
    end

    def sign_out_for_reset_link
      return unless user_signed_in? && params[:reset_password_token].present?

      sign_out(current_user)
    end
  end
end

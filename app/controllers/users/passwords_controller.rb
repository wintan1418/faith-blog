# frozen_string_literal: true

module Users
  # Password reset. Devise sends anyone who is already signed in away from the
  # reset form (straight to the feed), but the reset link often opens in the
  # app or a browser where the person is still signed in. A valid reset link
  # wins: sign them out and show the form.
  class PasswordsController < Devise::PasswordsController
    include AuthRateLimiting

    prepend_before_action :sign_out_for_reset_link, only: :edit
    throttle_auth only: :create, per_ip: 5, per_email: 3, within: 15.minutes
    before_action :verify_turnstile, only: :create

    private

    # Password-reset emails can be abused to spam people; when Turnstile is on
    # the reset form carries the challenge too.
    def verify_turnstile
      return unless SignupGuard.turnstile_enabled?
      return if SignupGuard.turnstile_passed?(params["cf-turnstile-response"], request.remote_ip)

      SignupGuard.record_block!("turnstile", where: "password reset", remote_ip: request.remote_ip,
                                             email: params.dig(:user, :email))
      self.resource = resource_class.new(email: params.dig(:user, :email))
      resource.errors.add(:base, "Please complete the check below and try again.")
      render :new, status: :unprocessable_entity
    end

    def sign_out_for_reset_link
      return unless user_signed_in? && params[:reset_password_token].present?

      sign_out(current_user)
    end
  end
end

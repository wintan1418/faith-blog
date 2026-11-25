# frozen_string_literal: true

# Security notices about the member's own account: codes, new sign-ins and
# changes. Each tells them what to do if it wasn't them. Only an approximate
# place (city / country) is ever shown, never an IP address.
class AccountSecurityMailer < ApplicationMailer
  helper_method :secure_url, :reset_url

  # A Google / Apple sign-in was just linked to this (password) account and
  # the old password was switched off.
  def linked_to_provider
    @user = params.fetch(:user)
    @provider_name = User::OAUTH_PROVIDER_NAMES.fetch(params[:provider].to_s, "Google")
    @reset_url = new_user_password_url
    mail(to: @user.email, subject: "[Brethreign] Your account is now linked to #{@provider_name}")
  end

  # A six-digit code (and one-tap link) to verify an address: the account's
  # own, or a new one before an email change.
  def verification_code
    @user = params.fetch(:user)
    @code = params.fetch(:code)
    @purpose = params.fetch(:purpose, "verify_email")
    @email = params.fetch(:email, @user.email)
    @link = confirm_email_verification_url(token: params[:link_token]) if params[:link_token]
    subject = @purpose == "change_email" ? "#{@code} is your code to confirm your new email" : "#{@code} is your Brethreign verification code"
    mail(to: @email, subject: subject)
  end

  # "Is this you signing in on Chrome on Windows near Lagos?"
  def sign_in_code
    @user = params.fetch(:user)
    @code = params.fetch(:code)
    @device_name = params[:device_name].presence || "a new device"
    @location = params[:location].presence
    @time = Time.current
    mail(to: @user.email, subject: "#{@code} is your Brethreign sign-in code")
  end

  # Signed in on a device we hadn't seen before.
  def new_sign_in
    @user = params.fetch(:user)
    @device_name = params[:device_name].presence || "a new device"
    @location = params[:location].presence
    @time = params[:at] || Time.current
    @method = { "google" => "Google", "apple" => "Apple", "password_reset" => "a new password" }[params[:method].to_s]
    mail(to: @user.email, subject: "New sign-in to your Brethreign account")
  end

  def password_changed
    @user = params.fetch(:user)
    mail(to: @user.email, subject: "Your Brethreign password was changed")
  end

  # Sent to the OLD address, with a link that switches back.
  def email_changed
    @user = params.fetch(:user)
    @old_email = params.fetch(:old_email)
    @new_email_masked = AccountSecurity.mask_email(params.fetch(:new_email))
    @secure_url = secure_account_url(token: @user.secure_account_token(revert_email: @old_email))
    mail(to: @old_email, subject: "Your Brethreign email address was changed")
  end

  def two_factor_enabled
    @user = params.fetch(:user)
    mail(to: @user.email, subject: "Two-step login is on for your Brethreign account")
  end

  def two_factor_disabled
    @user = params.fetch(:user)
    @by_admin = params[:by_admin]
    mail(to: @user.email, subject: "Two-step login is off for your Brethreign account")
  end

  def account_unlocked
    @user = params.fetch(:user)
    mail(to: @user.email, subject: "Your Brethreign account is unlocked")
  end

  private

  def secure_url = @secure_url || secure_account_url(token: @user.secure_account_token)
  def reset_url = new_user_password_url
end

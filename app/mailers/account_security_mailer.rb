# frozen_string_literal: true

# Security notices about the member's own account.
class AccountSecurityMailer < ApplicationMailer
  # A Google / Apple sign-in was just linked to this (password) account and
  # the old password was switched off.
  def linked_to_provider
    @user = params.fetch(:user)
    @provider_name = User::OAUTH_PROVIDER_NAMES.fetch(params[:provider].to_s, "Google")
    @reset_url = new_user_password_url
    mail(to: @user.email, subject: "[Brethreign] Your account is now linked to #{@provider_name}")
  end
end

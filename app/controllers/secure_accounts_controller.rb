# frozen_string_literal: true

# "Wasn't you? Secure your account" from a security email. Opening the link
# only explains what will happen (link scanners open links); the button
# signs out every device, switches off the password, turns off two-step login
# (someone else may have turned it on), emails a link to choose a new
# password, and after an email change, switches back to the old address.
class SecureAccountsController < ApplicationController
  before_action :load_user

  def show
  end

  def create
    sign_out(current_user) if user_signed_in? && current_user.id == @user.id
    @user.secure_account!(revert_email: @revert_email)
    SecurityEvent.record!(:account_secured, user: @user, request: request, reverted_email: @revert_email.present? || nil)
    redirect_to new_user_session_path, status: :see_other,
      notice: "Your account is secured: every device is signed out. Check #{@user.masked_email} for a link to choose a new password."
  end

  private

  def load_user
    @user, @revert_email = AccountSecurity.from_secure_account_token(params[:token])
    return if @user

    redirect_to new_user_password_path, alert: "That link has expired. You can still reset your password here."
  end
end

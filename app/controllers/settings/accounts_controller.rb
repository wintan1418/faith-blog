# frozen_string_literal: true

class Settings::AccountsController < ApplicationController
  before_action :authenticate_user!

  def edit
  end

  # Members who know their password must type it to change email or
  # password. Google / Apple accounts (random password nobody knows) must
  # have signed in within the last RECENT_SIGN_IN instead. Either way Devise
  # emails the OLD address about an email change and the member about a
  # password change.
  RECENT_SIGN_IN = 15.minutes

  def update
    attrs = account_params
    if sensitive_change?(attrs)
      if current_user.password_known?
        saved = current_user.update_with_password(attrs.merge(current_password: params.dig(:user, :current_password).to_s))
      elsif recently_signed_in?
        saved = current_user.update(attrs)
      else
        current_user.assign_attributes(attrs.except(:password, :password_confirmation))
        current_user.errors.add(:base, "For your safety, sign in again with #{current_user.oauth_provider_name} and then change your email or password within #{RECENT_SIGN_IN.inspect}.")
        saved = false
      end
    else
      saved = current_user.update(attrs.except(:password, :password_confirmation))
    end

    if saved
      bypass_sign_in(current_user)
      recede_or_redirect_to edit_settings_account_path, notice: "Account updated successfully!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # GET /settings/account/delete — explain what happens and ask for confirmation.
  def delete
  end

  # DELETE /settings/account — permanently delete the account and its content.
  # Confirmed by typing the username (works for Google sign-in users too,
  # who never set a password).
  def destroy
    unless params[:confirm_username].to_s.strip.casecmp?(current_user.username)
      flash.now[:alert] = "That doesn't match your username. Your account was not deleted."
      render :delete, status: :unprocessable_entity
      return
    end

    user = current_user
    # Disconnect from their Apple ID too (Apple requires it for Sign in with Apple).
    AppleTokenRevokeJob.perform_later(user.apple_refresh_token) if user.apple_refresh_token.present?
    user.destroy!
    sign_out(user)
    redirect_to root_path, status: :see_other,
      notice: "Your account and everything you shared have been deleted. Go in peace."
  end

  private

  def account_params
    params.require(:user).permit(:email, :username, :password, :password_confirmation)
  end

  def sensitive_change?(attrs)
    attrs[:password].present? ||
      (attrs.key?(:email) && !attrs[:email].to_s.strip.casecmp?(current_user.email.to_s))
  end

  def recently_signed_in?
    current_user.current_sign_in_at.present? && current_user.current_sign_in_at > RECENT_SIGN_IN.ago
  end
end

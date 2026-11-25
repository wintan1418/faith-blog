# frozen_string_literal: true

class Settings::AccountsController < ApplicationController
  before_action :authenticate_user!

  def edit
  end

  # Members who know their password must type it to change email or
  # password. Google / Apple accounts (random password nobody knows) must
  # have signed in within the last RECENT_SIGN_IN instead.
  #
  # A new email isn't switched to straight away: a code goes to the new
  # address (Settings::EmailChangesController) and the old address is told
  # once it changes. Changing the password needs a verified email first.
  RECENT_SIGN_IN = 15.minutes

  def update
    attrs = account_params
    new_email = attrs.delete(:email).to_s.strip.downcase
    email_change = new_email.present? && !new_email.casecmp?(current_user.email.to_s)
    password_change = attrs[:password].present?

    if password_change && !current_user.email_verified?
      current_user.assign_attributes(attrs.except(:password, :password_confirmation))
      current_user.errors.add(:base, "Please verify your email address before changing your password.")
      return render(:edit, status: :unprocessable_entity)
    end
    return render(:edit, status: :unprocessable_entity) if email_change && !acceptable_new_email?(new_email, attrs)

    if email_change || password_change
      if current_user.password_known?
        saved = current_user.update_with_password(attrs.merge(current_password: nested_param(:user, :current_password).to_s))
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

    return render(:edit, status: :unprocessable_entity) unless saved

    bypass_sign_in(current_user)
    if email_change
      start_email_change(new_email)
    else
      recede_or_redirect_to edit_settings_account_path, notice: "Account updated successfully!"
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
    params.expect(user: [ :email, :username, :password, :password_confirmation ])
  end

  def acceptable_new_email?(new_email, attrs)
    current_user.assign_attributes(attrs.except(:password, :password_confirmation))
    problem = if !new_email.match?(Devise.email_regexp) then "Email is not a valid address"
    elsif User.where.not(id: current_user.id).exists?(email: new_email) then "Email is already used by another account"
    elsif DisposableEmail.disposable?(new_email) then "Email from a throwaway email service can't be used. Please use your personal email"
    end
    current_user.errors.add(:base, problem) if problem
    problem.nil?
  end

  def start_email_change(new_email)
    EmailVerification.send_change_code!(current_user, new_email, request: request)
    session[Settings::EmailChangesController::PENDING_KEY] = new_email
    redirect_to settings_email_change_path, status: :see_other, notice: "We sent a 6-digit code to #{new_email}."
  rescue SecurityCode::RateLimited => e
    session[Settings::EmailChangesController::PENDING_KEY] = new_email
    redirect_to settings_email_change_path, status: :see_other, alert: e.message
  end

  def recently_signed_in?
    current_user.current_sign_in_at.present? && current_user.current_sign_in_at > RECENT_SIGN_IN.ago
  end
end

# frozen_string_literal: true

# Confirming a new email address with the code sent to it. The account keeps
# its old address until the new one is proven; then the old address is told.
class Settings::EmailChangesController < ApplicationController
  PENDING_KEY = "pending_email_change"

  before_action :authenticate_user!
  before_action :load_pending

  def show
    @cooldown = SecurityCode.cooldown_for(current_user, :change_email)
  end

  def update
    if SecurityEvent.failures_from_ip(request.remote_ip) >= EmailVerificationsController::MAX_IP_FAILURES
      return refuse(AuthRateLimiting::TOO_MANY_MESSAGE)
    end

    result = SecurityCode.check(user: current_user, purpose: :change_email, code: params[:code], email: @new_email)
    unless result.ok?
      SecurityEvent.record!(:code_failed, user: current_user, request: request, purpose: "change_email")
      return refuse(result.status == :wrong ? "That code didn't match. Check the newest email at #{@new_email}." : "That code has expired. Tap \"Send a new code\".")
    end

    session.delete(PENDING_KEY)
    if EmailVerification.change_email!(current_user, @new_email, request: request)
      bypass_sign_in(current_user)
      redirect_to settings_security_path, status: :see_other, notice: "Your email is now #{@new_email}, and it's verified."
    else
      redirect_to edit_settings_account_path, status: :see_other, alert: current_user.errors.full_messages.to_sentence
    end
  end

  def resend
    EmailVerification.send_change_code!(current_user, @new_email, request: request)
    redirect_to settings_email_change_path, status: :see_other, notice: "We sent a new code to #{@new_email}."
  rescue SecurityCode::RateLimited => e
    redirect_to settings_email_change_path, status: :see_other, alert: e.message
  end

  def destroy
    session.delete(PENDING_KEY)
    redirect_to edit_settings_account_path, status: :see_other, notice: "Email change cancelled. Your email is still #{current_user.email}."
  end

  private

  def load_pending
    @new_email = session[PENDING_KEY].to_s.presence
    redirect_to edit_settings_account_path unless @new_email
  end

  def refuse(message)
    @error = message
    @cooldown = SecurityCode.cooldown_for(current_user, :change_email)
    render :show, status: :unprocessable_entity
  end
end

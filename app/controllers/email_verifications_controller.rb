# frozen_string_literal: true

# "Check your email": verify the account's address with a six-digit code, or
# the one-tap link in the same email. Nothing is blocked for members who
# haven't verified yet; a few sensitive actions ask for it first.
class EmailVerificationsController < ApplicationController
  before_action :authenticate_user!, except: :confirm
  before_action :redirect_verified, only: %i[show create update]

  MAX_IP_FAILURES = 30
  CODE_ERRORS = {
    expired: "That code has expired. Tap \"Send a new code\" for a fresh one.",
    too_many: "Too many wrong tries. Tap \"Send a new code\" for a fresh one.",
    wrong: "That code didn't match. Check the newest email from Brethreign and try again."
  }.freeze

  def show
    @return_to = safe_return_to
    @cooldown = SecurityCode.cooldown_for(current_user, :verify_email)
    @code_sent = SecurityCode.live.exists?(user: current_user, purpose: "verify_email")
  end

  # Send (or resend) the code.
  def create
    EmailVerification.send_code!(current_user, request: request)
    redirect_to email_verification_path(return_to: safe_return_to), status: :see_other,
      notice: "We sent a 6-digit code to #{current_user.email}."
  rescue SecurityCode::RateLimited => e
    redirect_to email_verification_path(return_to: safe_return_to), status: :see_other, alert: e.message
  end

  # Check the typed code.
  def update
    if SecurityEvent.failures_from_ip(request.remote_ip) >= MAX_IP_FAILURES
      return refuse(AuthRateLimiting::TOO_MANY_MESSAGE)
    end

    result = SecurityCode.check(user: current_user, purpose: :verify_email, code: params[:code], email: current_user.email)
    if result.ok?
      EmailVerification.verified!(current_user, request: request)
      redirect_to safe_return_to || feed_path, status: :see_other, notice: "Thank you! Your email is verified."
    else
      SecurityEvent.record!(:code_failed, user: current_user, request: request, purpose: "verify_email")
      refuse(CODE_ERRORS.fetch(result.status, CODE_ERRORS[:wrong]))
    end
  end

  # GET /verify-email/:token — the one-tap link. Works signed out too (it may
  # open in another browser); proving the inbox is all it does.
  def confirm
    status, user = EmailVerification.redeem_link(params[:token], request: request)
    signed_in_as_owner = user_signed_in? && user && current_user.id == user.id
    destination = signed_in_as_owner ? feed_path : (user_signed_in? ? feed_path : new_user_session_path)
    case status
    when :verified
      redirect_to destination, notice: "Thank you! Your email is verified."
    when :changed
      redirect_to(signed_in_as_owner ? settings_security_path : destination, notice: "Your email address is updated and verified.")
    when :taken
      redirect_to destination, alert: "That email address is already used by another account, so your email wasn't changed."
    else
      redirect_to(user_signed_in? ? email_verification_path : new_user_session_path,
                  alert: "That link has expired or was already used. You can ask for a new code.")
    end
  end

  private

  def refuse(message)
    @error = message
    @return_to = safe_return_to
    @cooldown = SecurityCode.cooldown_for(current_user, :verify_email)
    @code_sent = true
    render :show, status: :unprocessable_entity
  end

  def redirect_verified
    redirect_to(safe_return_to || settings_security_path, notice: "Your email is already verified.") if current_user.email_verified?
  end

  # Only paths on this site ("/settings/…"), never "//elsewhere.com".
  def safe_return_to
    path = params[:return_to].to_s
    path if path.start_with?("/") && !path.start_with?("//") && !path.include?("\\") && path.length < 300
  end
end

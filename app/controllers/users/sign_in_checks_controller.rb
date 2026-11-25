# frozen_string_literal: true

module Users
  # "Is this you?" — the code screen between a correct password (or Google /
  # Apple) and being signed in. See SignInChecks.
  class SignInChecksController < ApplicationController
    include SignInChecks

    MAX_IP_FAILURES = 30 # wrong codes from one IP, across every account, per 15 minutes

    before_action :redirect_signed_in, except: :destroy
    before_action :load_pending, except: :destroy

    def show
      @info = DeviceInfo.from(request)
      @cooldown = SecurityCode.cooldown_for(@user, :sign_in) if @step == "email_code"
    end

    def create
      if SecurityEvent.failures_from_ip(request.remote_ip) >= MAX_IP_FAILURES
        return refuse(AuthRateLimiting::TOO_MANY_MESSAGE)
      end

      @step == "otp" ? check_authenticator : check_email_code
    end

    def resend
      return redirect_to(sign_in_check_path) unless @step == "email_code"

      flash[:notice] = "We sent a new code to #{@user.masked_email}." if send_sign_in_code(@user)
      redirect_to sign_in_check_path, status: :see_other
    end

    # "Not you? Cancel" — forget the half-finished sign-in.
    def destroy
      session.delete(PENDING_KEY)
      redirect_to new_user_session_path, status: :see_other, notice: "Sign-in cancelled."
    end

    private

    def check_email_code
      result = SecurityCode.check(user: @user, purpose: :sign_in, code: params[:code])
      return finish(trust: params[:trust_device] == "1") if result.ok?

      SecurityEvent.record!(:code_failed, user: @user, request: request, purpose: "sign_in")
      refuse(code_error(result.status))
    end

    def check_authenticator
      return locked_out! if @user.access_locked?

      recovery = params[:recovery_code].present?
      ok = recovery ? @user.use_recovery_code!(params[:recovery_code]) : @user.verify_otp(params[:code])
      if ok
        SecurityEvent.record!(:recovery_code_used, user: @user, request: request, left: @user.reload.recovery_codes_left) if recovery
        return finish(trust: params[:trust_device] == "1")
      end

      SecurityEvent.record!(:two_factor_failed, user: @user, request: request, recovery: recovery || nil)
      # Wrong authenticator codes count towards the same lock as wrong passwords.
      @user.increment_failed_attempts
      if @user.failed_attempts.to_i >= Devise.maximum_attempts
        @user.lock_access! unless @user.access_locked?
        return locked_out!
      end
      refuse(recovery ? "That recovery code didn't work. Each one works only once." : "That code didn't match. Check your authenticator app and try again.")
    end

    def finish(trust:)
      finish_pending_sign_in(@user, @data, trust: trust)
      redirect_to after_sign_in_path_for(@user), status: :see_other, notice: "Welcome back! You're signed in."
    end

    def code_error(status)
      case status
      when :too_many then "Too many wrong tries. Tap \"Send a new code\" to get a fresh one."
      when :expired then "That code has expired. Tap \"Send a new code\" to get a fresh one."
      else "That code didn't match. Check the newest email from Brethreign and try again."
      end
    end

    def refuse(message)
      @error = message
      @info = DeviceInfo.from(request)
      @cooldown = SecurityCode.cooldown_for(@user, :sign_in) if @step == "email_code"
      render :show, status: :unprocessable_entity
    end

    def locked_out!
      session.delete(PENDING_KEY)
      redirect_to new_user_session_path, status: :see_other,
        alert: "Too many wrong codes. For your safety this account is locked for an hour. We've emailed you a link to unlock it."
    end

    def redirect_signed_in
      redirect_to feed_path if user_signed_in?
    end

    def load_pending
      @user, @data = pending_sign_in
      return redirect_to(new_user_session_path, alert: "That sign-in has expired. Please sign in again.") unless @user

      unless @user.active_for_authentication?
        session.delete(PENDING_KEY)
        return redirect_to(new_user_session_path, alert: I18n.t("devise.failure.#{@user.inactive_message}", default: "This account can't sign in right now."))
      end

      @step = @data["step"]
    end
  end
end

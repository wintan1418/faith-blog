# frozen_string_literal: true

# The step between "password (or Google / Apple) accepted" and "signed in":
#
#   otp         — two-step login is on: the authenticator app's code (or a
#                 recovery code). Skipped on a device trusted in the last 30 days.
#   email_code  — a password sign-in from a device we don't recognise, on an
#                 account whose email is verified: a code emailed to that address.
#
# Accounts whose email isn't verified yet never get an emailed code (it could
# go to a mistyped address and lock them out); they get the new-sign-in alert.
# Google and Apple have already proven the address, so they only ever meet otp.
#
# The half-finished sign-in lives in the session for PENDING_TTL, tied to the
# password it was started with.
module SignInChecks
  extend ActiveSupport::Concern

  PENDING_KEY = "pending_sign_in"
  PENDING_TTL = 15.minutes

  private

  def sign_in_steps_for(user, method:)
    return [] if user.site_monitor?
    if user.two_factor_enabled?
      return AccountDevices.trusted?(user, request) ? [] : [ "otp" ]
    end
    return [] unless method == "password" && user.email_verified?

    AccountDevices.recognised?(user, request) ? [] : [ "email_code" ]
  end

  # Starts the check when one is needed and returns where to send them; nil
  # means sign them in now.
  def begin_sign_in_check(user, method:, remember: true)
    step = sign_in_steps_for(user, method: method).first
    return nil unless step

    session[PENDING_KEY] = { "user_id" => user.id, "method" => method, "remember" => remember ? true : false,
                             "step" => step, "at" => Time.current.to_i, "salt" => user.authenticatable_salt }
    SecurityEvent.record!(:sign_in_challenged, user: user, request: request, step: step, method: method)
    send_sign_in_code(user) if step == "email_code"
    sign_in_check_path
  end

  # [user, data] for a live pending sign-in, else nil (and it's cleared).
  def pending_sign_in
    data = session[PENDING_KEY]
    return nil unless data.is_a?(Hash)

    user = User.find_by(id: data["user_id"])
    fresh = data["at"].to_i > PENDING_TTL.ago.to_i
    if user.nil? || !fresh || !ActiveSupport::SecurityUtils.secure_compare(user.authenticatable_salt.to_s, data["salt"].to_s)
      session.delete(PENDING_KEY)
      return nil
    end
    [ user, data ]
  end

  def send_sign_in_code(user)
    issued = SecurityCode.issue!(user: user, purpose: :sign_in, ip: request.remote_ip)
    info = DeviceInfo.from(request)
    AccountSecurityMailer.with(user: user, code: issued.code, device_name: info.name, location: info.location)
                         .sign_in_code.deliver_later
    SecurityEvent.record!(:code_sent, user: user, request: request, purpose: "sign_in")
    true
  rescue SecurityCode::RateLimited => e
    flash[:alert] = e.message
    false
  end

  def finish_pending_sign_in(user, data, trust:)
    session.delete(PENDING_KEY)
    request.env[AccountDevices::SIGN_IN_OPTIONS] = {
      method: data["method"], verified: trust, trust_two_factor: data["step"] == "otp" && trust
    }
    user.remember_me = data["remember"] if user.respond_to?(:remember_me=)
    sign_in(:user, user)
  end
end

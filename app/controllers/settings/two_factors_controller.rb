# frozen_string_literal: true

# Two-step login with an authenticator app (Google Authenticator, Authy,
# 1Password, Microsoft Authenticator…), and its one-time recovery codes.
class Settings::TwoFactorsController < ApplicationController
  include RequiresVerifiedEmail

  SETUP_KEY = "otp_setup"
  CODES_KEY = "otp_recovery_codes_once"
  SETUP_TTL = 30.minutes

  before_action :authenticate_user!
  before_action -> { require_verified_email!(return_to: new_settings_two_factor_path) }, only: %i[new create]
  before_action :require_off, only: %i[new create]
  before_action :require_on, only: %i[destroy recovery_codes show_recovery_codes]

  # Scan the QR code (or type the key) into the app, then type its code.
  def new
    prepare_setup
  end

  def create
    secret = setup_secret(create: false)
    step = secret && AccountSecurity.verify_totp(secret, params[:code])
    unless step
      @error = secret ? "That code didn't match. Make sure your phone's time is set automatically, then try the newest code." : "That setup expired. Please scan the new code."
      prepare_setup
      return render :new, status: :unprocessable_entity
    end

    session.delete(SETUP_KEY)
    @recovery_codes = current_user.enable_two_factor!(secret, step)
    # This device just proved it holds the app: no code here for 30 days.
    current_user.user_devices.where(id: Current.user_device_id).update_all(trusted_until: UserDevice::TRUST_FOR.from_now, verified_at: Time.current)
    SecurityEvent.record!(:two_factor_enabled, user: current_user, request: request)
    AccountSecurityMailer.with(user: current_user).two_factor_enabled.deliver_later
    show_codes_once(@recovery_codes, fresh: true)
  end

  # Turning it off needs the password (when they know one) or a current code.
  def destroy
    unless confirmed_by_member?
      return redirect_to(settings_security_path(anchor: "two-step"), status: :see_other,
                         alert: "That didn't match. Enter your password, or a code from your authenticator app.")
    end

    current_user.disable_two_factor!
    SecurityEvent.record!(:two_factor_disabled, user: current_user, request: request)
    AccountSecurityMailer.with(user: current_user).two_factor_disabled.deliver_later
    redirect_to settings_security_path, status: :see_other, notice: "Two-step login is off."
  end

  # Fresh recovery codes (the old ones stop working); needs a current code.
  def recovery_codes
    code = params[:code].to_s
    ok = current_user.verify_otp(code) || current_user.use_recovery_code!(code)
    unless ok
      return redirect_to(settings_security_path(anchor: "two-step"), status: :see_other,
                         alert: "That code didn't match. Use the newest code from your authenticator app.")
    end

    codes = current_user.regenerate_recovery_codes!
    SecurityEvent.record!(:recovery_codes_regenerated, user: current_user, request: request)
    show_codes_once(codes, fresh: false)
  end

  # GET — the codes just made, once (they're never stored in a readable form).
  def show_recovery_codes
    data = session.delete(CODES_KEY)
    return redirect_to(settings_security_path) unless data.is_a?(Hash) && data["codes"].is_a?(Array)

    @recovery_codes = data["codes"]
    @fresh = data["fresh"]
    render :recovery_codes
  end

  private

  # Turbo wants a redirect after a form, so the codes ride in the (encrypted)
  # session to the next page, which shows them and forgets them.
  def show_codes_once(codes, fresh:)
    session[CODES_KEY] = { "codes" => codes, "fresh" => fresh }
    redirect_to recovery_codes_settings_two_factor_path, status: :see_other
  end

  def confirmed_by_member?
    password = params[:current_password].to_s
    code = params[:code].to_s
    return true if password.present? && current_user.password_known? && current_user.valid_password?(password)
    return false if code.blank?

    current_user.verify_otp(code) || current_user.use_recovery_code!(code)
  end

  def prepare_setup
    @secret = setup_secret
    @uri = AccountSecurity.provisioning_uri(@secret, current_user.email)
    @qr_svg = RQRCode::QRCode.new(@uri, level: :m).as_svg(color: "0b1110", module_size: 5, standalone: true,
                                                            use_path: true, viewbox: true, offset: 12)
  end

  # The secret being set up lives (encrypted) in the session until it's proven.
  def setup_secret(create: true)
    data = session[SETUP_KEY]
    if data.is_a?(Hash) && data["at"].to_i > SETUP_TTL.ago.to_i
      secret = AccountSecurity.decrypt_secret(data["box"])
      return secret if secret
    end
    return nil unless create

    secret = AccountSecurity.new_otp_secret
    session[SETUP_KEY] = { "box" => AccountSecurity.encrypt_secret(secret), "at" => Time.current.to_i }
    secret
  end

  def require_off
    redirect_to settings_security_path, notice: "Two-step login is already on." if current_user.two_factor_enabled?
  end

  def require_on
    redirect_to settings_security_path, status: :see_other, notice: "Two-step login is off." unless current_user.two_factor_enabled?
  end
end

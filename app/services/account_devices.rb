# frozen_string_literal: true

# Devices & sessions: which phone or browser a member is signed in on, and
# signing them out remotely.
#
# A browser is recognised by a long-lived signed cookie; the iPhone / Android
# apps may send a stable install id header instead. Only keyed hashes of
# either are stored. Every sign-in puts a random token in the (encrypted)
# session and its hash on the device row; each signed-in request checks the
# row is still signed in (ApplicationController#check_device_session).
#
# Sessions that began before this existed carry no token. They are adopted
# quietly on their next request (no one is signed out by the rollout), unless
# the member has since chosen "Sign out everywhere else" (users.sessions_reset_at).
module AccountDevices
  COOKIE = :_brethreign_device
  SESSION_KEY = "device_session"
  INSTALL_HEADER = "X-Brethreign-Install-Id"
  # Set by a controller just before sign_in to describe the sign-in:
  #   method: "password" | "google" | "apple" | "signup" | ... ; verified: false (don't
  #   recognise the device); trust_two_factor: true; alert: false
  SIGN_IN_OPTIONS = "brethreign.sign_in_options"

  module_function

  def digest(value) = SecurityCode.digest(value)

  def install_id(request)
    request.headers[INSTALL_HEADER].to_s[/\A[A-Za-z0-9_-]{16,128}\z/]
  end

  def cookie_id(request)
    request.env["brethreign.device_cookie"] ||= begin
      jar = request.cookie_jar
      id = jar.signed[COOKIE].to_s
      unless id.match?(/\A[A-Za-z0-9_-]{20,64}\z/)
        id = SecureRandom.urlsafe_base64(24)
        jar.signed.permanent[COOKIE] = { value: id, httponly: true, same_site: :lax, secure: Rails.env.production? }
      end
      id
    end
  end

  def device_digest(request)
    install = install_id(request)
    digest(install ? "device:install:#{install}" : "device:cookie:#{cookie_id(request)}")
  end

  def find_for(user, request)
    user.user_devices.find_by(device_digest: device_digest(request))
  end

  def recognised?(user, request) = find_for(user, request)&.recognised? || false
  def trusted?(user, request) = find_for(user, request)&.trusted? || false

  def current(user, request)
    token = request.session[SESSION_KEY]
    token.present? ? user.user_devices.find_by(session_digest: digest(token)) : nil
  end

  # Warden hook: a member has just signed in (any way: password, Google, Apple,
  # sign-up, password reset, a remember-me cookie, or after a sign-in check).
  def signed_in!(user, request, strategy: nil)
    return if user.site_monitor?

    opts = request.env.delete(SIGN_IN_OPTIONS) || {}
    method = opts[:method] || (strategy == :rememberable ? "remembered" : "password")
    info = DeviceInfo.from(request)
    token = SecureRandom.urlsafe_base64(32)
    now = Time.current
    device = nil
    unknown = false
    2.times do
      device = UserDevice.find_or_initialize_by(user_id: user.id, device_digest: device_digest(request))
      unknown = !device.recognised?
      device.assign_attributes(name: info.name, platform: info.platform, user_agent: info.user_agent, ip: info.ip,
                               location: info.location, session_digest: digest(token), signed_in_at: now,
                               last_active_at: now, signed_out_at: nil)
      device.verified_at ||= now unless opts[:verified] == false
      device.trusted_until = now + UserDevice::TRUST_FOR if opts[:trust_two_factor]
      device.save!
      break
    rescue ActiveRecord::RecordNotUnique
      next
    end
    request.session[SESSION_KEY] = token
    Current.user_device_id = device.id

    unless opts[:event] == false
      SecurityEvent.record!(:sign_in, user: user, request: request, device_name: info.name, location: info.location,
                                      method: method, new_device: unknown || nil)
    end
    alert_new_device(user, info, method) if unknown && opts[:alert] != false && method != "signup"
    device
  rescue StandardError => e
    Rails.logger.error("[AccountDevices] sign-in record failed for user #{user.id}: #{e.class}: #{e.message}")
    nil
  end

  def alert_new_device(user, info, method)
    return if user.email.blank?

    AccountSecurityMailer.with(user: user, device_name: info.name, location: info.location, at: Time.current,
                               method: method).new_sign_in.deliver_later
  end

  # Warden hook: signing out here ends this device's session (it stays recognised).
  def signed_out!(user, request)
    token = request.session[SESSION_KEY]
    return if token.blank? || user.nil?

    UserDevice.where(user_id: user.id, session_digest: digest(token))
              .update_all(session_digest: nil, signed_out_at: Time.current, updated_at: Time.current)
    request.session.delete(SESSION_KEY)
  rescue StandardError => e
    Rails.logger.warn("[AccountDevices] sign-out record failed: #{e.class}: #{e.message}")
  end

  # Before each signed-in request: :ok, or :ended when this device was signed
  # out from elsewhere.
  def check(user, request)
    return :ok if user.site_monitor?

    token = request.session[SESSION_KEY]
    if token.blank?
      return :ended if user.sessions_reset_at.present?

      # A session from before devices were tracked: adopt it silently.
      request.env[SIGN_IN_OPTIONS] = { method: "existing", alert: false, event: false }
      signed_in!(user, request)
      return :ok
    end

    device = UserDevice.find_by(session_digest: digest(token))
    # Two requests that sign in at once on the same browser (a remember-me
    # cookie restoring several tabs) each write a token; only one is kept on
    # the row. The device itself is still signed in, so that's fine.
    device ||= find_for(user, request)&.then { |same| same if same.signed_in? }
    return :ended unless device && device.user_id == user.id && device.signed_out_at.nil?

    Current.user_device_id = device.id
    touch(device, request)
    :ok
  end

  def touch(device, request)
    return if device.last_active_at && device.last_active_at > UserDevice::TOUCH_EVERY.ago

    device.update_columns(last_active_at: Time.current, ip: request.remote_ip,
                          location: DeviceInfo.location_for(request) || device.location)
  rescue StandardError => e
    Rails.logger.warn("[AccountDevices] touch failed: #{e.class}: #{e.message}")
  end

  # "Sign out" on one device in Settings → Security.
  def sign_out_device!(user, device)
    device.sign_out!
    rotate_remember_tokens!(user)
  end

  # "Sign out everywhere else": every other device, every session from before
  # devices were tracked, every remember-me cookie, and the push tokens of
  # phones that are no longer signed in.
  def sign_out_others!(user, request, forget: true)
    current = current(user, request)
    user.user_devices.where.not(id: current&.id).find_each { |device| device.sign_out!(forget: forget) }
    pushes = ApplicationPushDevice.where(owner: user)
    pushes = pushes.where.not(token: current.push_token) if current&.push_token.present?
    pushes.destroy_all
    user.update_columns(sessions_reset_at: Time.current)
    rotate_remember_tokens!(user)
  end

  # Every remember-me cookie issued before now stops working (Devise checks the
  # cookie was made after remember_created_at). The caller re-issues one for
  # the current browser.
  def rotate_remember_tokens!(user)
    user.update_columns(remember_created_at: Time.current)
  end

  # Ends everything: used by "Wasn't you? Secure your account".
  def sign_out_everywhere!(user)
    user.user_devices.find_each { |device| device.sign_out!(forget: true) }
    ApplicationPushDevice.where(owner: user).destroy_all
    user.update_columns(sessions_reset_at: Time.current, remember_created_at: nil)
  end
end

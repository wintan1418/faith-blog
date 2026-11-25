# frozen_string_literal: true

# Sending and accepting the codes that verify a member's email address, and
# confirm a new address before an email change.
module EmailVerification
  module_function

  # Emails a verify-email code + one-tap link. Returns the Issued code, or
  # raises SecurityCode::RateLimited.
  def send_code!(user, request: nil)
    issued = SecurityCode.issue!(user: user, purpose: :verify_email, ip: request&.remote_ip, link: true)
    AccountSecurityMailer.with(user: user, code: issued.code, link_token: issued.link_token, email: user.email,
                               purpose: "verify_email").verification_code.deliver_later
    SecurityEvent.record!(:code_sent, user: user, request: request, purpose: "verify_email")
    issued
  end

  # The same, but never raises (sign-up must not fail because of a limit).
  def send_code(user, request: nil)
    return if user.email_verified? || user.site_monitor?

    send_code!(user, request: request)
  rescue SecurityCode::RateLimited
    nil
  rescue StandardError => e
    Rails.logger.warn("[EmailVerification] code for user #{user.id} not sent: #{e.class}: #{e.message}")
    nil
  end

  def send_change_code!(user, new_email, request: nil)
    issued = SecurityCode.issue!(user: user, purpose: :change_email, email: new_email, ip: request&.remote_ip, link: true)
    AccountSecurityMailer.with(user: user, code: issued.code, link_token: issued.link_token, email: new_email,
                               purpose: "change_email").verification_code.deliver_later
    SecurityEvent.record!(:code_sent, user: user, request: request, purpose: "change_email")
    issued
  end

  def verified!(user, request: nil)
    return if user.email_verified?

    user.mark_email_verified!
    SecurityEvent.record!(:email_verified, user: user, request: request)
  end

  # Switches to the new address once it's proven. Returns the user with
  # errors when the address was taken meanwhile.
  def change_email!(user, new_email, request: nil)
    old = user.email
    user.email_verified_by_code = true
    if user.update(email: new_email)
      SecurityEvent.record!(:email_changed, user: user, request: request, from: AccountSecurity.mask_email(old))
      true
    else
      false
    end
  end

  # A one-tap link from an email. Returns [status, user]: :verified,
  # :changed, :taken (the new address belongs to someone else now) or :invalid.
  def redeem_link(token, request: nil)
    record = SecurityCode.redeem_link(token)
    return [ :invalid, nil ] unless record

    user = record.user
    case record.purpose
    when "verify_email"
      return [ :invalid, user ] unless record.email.casecmp?(user.email.to_s)

      verified!(user, request: request)
      [ :verified, user ]
    when "change_email"
      return [ :changed, user ] if record.email.casecmp?(user.email.to_s)

      change_email!(user, record.email, request: request) ? [ :changed, user ] : [ :taken, user ]
    else
      [ :invalid, user ]
    end
  end
end

# frozen_string_literal: true

# Helpers for the account-security tests (codes, sign-in checks, devices).
module AccountSecurityHelpers
  # A member with a password we know. Verified email unless verified: false.
  def security_member(username, verified: true, **attrs)
    password = SecureRandom.base58(20)
    user = User.create!(username: username, email: "#{username}@example.com", password: password,
                        email_verified_at: (verified ? 1.day.ago : nil), **attrs)
    [ user, password ]
  end

  def password_sign_in(user, password, remember: "1", headers: {})
    post user_session_path, params: { user: { email: user.email, password: password, remember_me: remember } }, headers: headers
  end

  # The newest six-digit code emailed (to an address, if given).
  def emailed_code(to: nil)
    mail = ActionMailer::Base.deliveries.reverse.find { |m| to.nil? || m.to.include?(to) }
    assert mail, "expected an email#{" to #{to}" if to}"
    mail.text_part.body.to_s[/\b\d{6}\b/]
  end

  # Emails sent while the block runs (deliver_later jobs are performed).
  def mails_during(&block)
    before = ActionMailer::Base.deliveries.size
    perform_enqueued_jobs(&block)
    ActionMailer::Base.deliveries.drop(before)
  end

  def totp_now(user_or_secret, at: Time.current)
    secret = user_or_secret.is_a?(User) ? user_or_secret.reload.otp_secret : user_or_secret
    ROTP::TOTP.new(secret).at(at)
  end

  # Turns on two-step login directly; returns the recovery codes.
  def enable_two_factor_for(user)
    secret = AccountSecurity.new_otp_secret
    user.enable_two_factor!(secret, (Time.current.to_i / 30) - 2)
  end
end

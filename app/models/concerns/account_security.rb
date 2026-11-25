# frozen_string_literal: true

# A member's account security: email verification, two-step login with an
# authenticator app (plus one-time recovery codes), devices, and the emails
# sent when something security-related changes.
module AccountSecurity
  extend ActiveSupport::Concern

  OTP_ISSUER = "Brethreign"
  OTP_INTERVAL = 30
  RECOVERY_CODE_COUNT = 10

  included do
    has_many :user_devices, dependent: :delete_all
    has_many :security_codes, dependent: :delete_all
    has_many :security_events, dependent: :delete_all

    scope :email_verified, -> { where.not(email_verified_at: nil) }
    scope :email_unverified, -> { where(email_verified_at: nil) }
    scope :two_factor_on, -> { where.not(otp_enabled_at: nil) }

    # Set when an email change was proven with a code / link, so the new
    # address counts as verified.
    attr_accessor :email_verified_by_code, :skip_security_notifications

    before_save :forget_verification_of_old_email, if: :will_save_change_to_email?
    after_update_commit :send_security_notifications
    after_update_commit :sign_out_other_devices, if: :saved_change_to_encrypted_password?
  end

  # ── Email verification ─────────────────────────────────────────────

  def email_verified? = email_verified_at.present?

  def mark_email_verified!
    update_column(:email_verified_at, Time.current) unless email_verified?
  end

  # "j•••@gmail.com" — for screens and emails that shouldn't spell out the address.
  def masked_email(address = email) = AccountSecurity.mask_email(address)

  def self.mask_email(address)
    name, domain = address.to_s.split("@", 2)
    return address.to_s if domain.blank?

    "#{name.first}#{'•' * [ [ name.length - 1, 1 ].max, 5 ].min}@#{domain}"
  end

  # ── Two-step login (TOTP) ──────────────────────────────────────────

  def two_factor_enabled? = otp_enabled_at.present? && otp_secret_ciphertext.present?

  def otp_secret = otp_secret_ciphertext.present? ? AccountSecurity.decrypt_secret(otp_secret_ciphertext) : nil

  def self.new_otp_secret = ROTP::Base32.random

  def self.totp(secret) = ROTP::TOTP.new(secret, issuer: OTP_ISSUER, interval: OTP_INTERVAL)

  def self.provisioning_uri(secret, email) = totp(secret).provisioning_uri(email)

  # The time step of a code that matches `secret`, or nil.
  def self.verify_totp(secret, code, after_step: nil)
    typed = code.to_s.gsub(/\D/, "")
    return nil unless typed.length == 6 && secret.present?

    # ROTP only accepts time steps strictly later than `after`'s step.
    after = after_step ? after_step * OTP_INTERVAL : nil
    at = totp(secret).verify(typed, drift_behind: OTP_INTERVAL, drift_ahead: OTP_INTERVAL, after: after)
    at && at / OTP_INTERVAL
  end

  # Checks an authenticator code (never the same code twice).
  def verify_otp(code)
    step = AccountSecurity.verify_totp(otp_secret, code, after_step: otp_last_used_step)
    return false unless step

    # Only one request may use a given step.
    self.class.where(id: id).where("otp_last_used_step IS NULL OR otp_last_used_step < ?", step)
        .update_all(otp_last_used_step: step) == 1
  end

  # A recovery code works once.
  def use_recovery_code!(code)
    normalized = AccountSecurity.normalize_recovery_code(code)
    return false if normalized.blank?

    digest = AccountSecurity.recovery_digest(id, normalized)
    return false unless otp_recovery_digests.include?(digest)

    self.class.where(id: id).where("? = ANY(otp_recovery_digests)", digest)
        .update_all([ "otp_recovery_digests = array_remove(otp_recovery_digests, ?)", digest ]) == 1
  end

  # Turns it on with a secret the member just proved they have; returns the
  # recovery codes to show once.
  def enable_two_factor!(secret, step)
    codes = AccountSecurity.generate_recovery_codes
    update_columns(otp_secret_ciphertext: AccountSecurity.encrypt_secret(secret), otp_enabled_at: Time.current,
                   otp_last_used_step: step, otp_recovery_digests: codes.map { |c| AccountSecurity.recovery_digest(id, c) })
    codes
  end

  def regenerate_recovery_codes!
    codes = AccountSecurity.generate_recovery_codes
    update_columns(otp_recovery_digests: codes.map { |c| AccountSecurity.recovery_digest(id, c) })
    codes
  end

  def disable_two_factor!
    update_columns(otp_secret_ciphertext: nil, otp_enabled_at: nil, otp_last_used_step: nil, otp_recovery_digests: [])
    user_devices.update_all(trusted_until: nil)
  end

  def recovery_codes_left = otp_recovery_digests.size

  def self.generate_recovery_codes
    Array.new(RECOVERY_CODE_COUNT) { SecureRandom.alphanumeric(8).downcase.scan(/.{4}/).join("-") }
  end

  def self.normalize_recovery_code(code)
    cleaned = code.to_s.downcase.gsub(/[^a-z0-9]/, "")
    cleaned.length == 8 ? cleaned.scan(/.{4}/).join("-") : nil
  end

  def self.recovery_digest(user_id, code) = SecurityCode.digest("recovery:#{user_id}:#{code}")

  def self.secret_box
    @secret_box ||= ActiveSupport::MessageEncryptor.new(
      Rails.application.key_generator.generate_key("brethreign otp secret v1", 32), cipher: "aes-256-gcm"
    )
  end

  def self.encrypt_secret(secret) = secret_box.encrypt_and_sign(secret)

  def self.decrypt_secret(ciphertext)
    secret_box.decrypt_and_verify(ciphertext)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  # ── "Wasn't you?" link ─────────────────────────────────────────────

  # A signed link that lets the owner lock everyone else out. After an email
  # change it also carries the old address, so it can switch back.
  def secure_account_token(revert_email: nil)
    AccountSecurity.verifier.generate({ "id" => id, "revert" => revert_email }, expires_in: 14.days, purpose: :secure_account)
  end

  def self.verifier = Rails.application.message_verifier(:secure_account)

  def self.from_secure_account_token(token)
    data = verifier.verified(token.to_s, purpose: :secure_account)
    data.is_a?(Hash) ? [ User.find_by(id: data["id"]), data["revert"].presence ] : [ nil, nil ]
  rescue StandardError
    [ nil, nil ]
  end

  # Signs out every device, switches off the password and emails a reset
  # link; after an email change, switches back to the old address first.
  def secure_account!(revert_email: nil)
    transaction do
      if revert_email.present? && !revert_email.casecmp?(email) && !self.class.where.not(id: id).exists?(email: revert_email.downcase)
        self.email_verified_by_code = true
        self.skip_security_notifications = true
        self.email = revert_email
      end
      self.password = Devise.friendly_token.first(32)
      self.password_generated = true
      self.skip_security_notifications = true
      skip_password_change_notification!
      self.failed_attempts = 0
      self.locked_at = nil
      self.unlock_token = nil
      save!(validate: false)
      # Someone else may have turned it on with their own phone.
      disable_two_factor!
    end
    AccountDevices.sign_out_everywhere!(self)
    send_reset_password_instructions
  end

  private

  def forget_verification_of_old_email
    return if new_record?

    self.email_verified_at = email_verified_by_code ? Time.current : nil
  end

  # A new password ends every other session (Devise checks the password salt
  # stored in each session); show those devices as signed out and stop
  # pushing to them.
  def sign_out_other_devices
    user_devices.signed_in.where.not(id: Current.user_device_id).find_each { |device| device.sign_out!(forget: false) }
  rescue StandardError => e
    Rails.logger.warn("[AccountSecurity] device sign-out for user #{id} failed: #{e.class}: #{e.message}")
  end

  def send_security_notifications
    return if skip_security_notifications || site_monitor? || email.blank?

    if saved_change_to_email? && email_before_last_save.present?
      old = email_before_last_save
      AccountSecurityMailer.with(user: self, old_email: old, new_email: email).email_changed.deliver_later
    end
    if saved_change_to_encrypted_password? && password_chosen_at.present? && !@skip_password_change_notification
      AccountSecurityMailer.with(user: self).password_changed.deliver_later
    end
    if saved_change_to_locked_at? && locked_at.nil? && locked_at_before_last_save.present?
      AccountSecurityMailer.with(user: self).account_unlocked.deliver_later
    end
  rescue StandardError => e
    Rails.logger.warn("[AccountSecurity] notification for user #{id} failed: #{e.class}: #{e.message}")
  end
end

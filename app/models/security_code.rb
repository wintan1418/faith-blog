# frozen_string_literal: true

# A six-digit code we email to prove someone can read an inbox:
#   verify_email  — confirming the address on the account (also has a one-tap link)
#   change_email  — confirming a new address before the account switches to it (also a link)
#   sign_in       — confirming a password sign-in from a device we don't recognise (code only:
#                   a link would let an email scanner approve the sign-in)
#
# Codes live in the database (never the cache), as keyed hashes. Each lasts
# TTL, dies after MAX_ATTEMPTS wrong guesses, and sending is limited per
# member and per IP.
class SecurityCode < ApplicationRecord
  PURPOSES = %w[verify_email change_email sign_in].freeze
  TTL = 10.minutes
  MAX_ATTEMPTS = 5
  RESEND_COOLDOWN = 60.seconds
  MAX_SENDS_PER_HOUR = 6   # per member, per purpose
  MAX_SENDS_PER_IP_HOUR = 30

  belongs_to :user

  validates :purpose, inclusion: { in: PURPOSES }

  scope :live, -> { where(consumed_at: nil).where(expires_at: Time.current..).where(attempts: ...MAX_ATTEMPTS) }

  Issued = Data.define(:record, :code, :link_token)
  Result = Data.define(:status, :record) do
    def ok? = status == :ok
  end

  class RateLimited < StandardError
    attr_reader :retry_in

    def initialize(retry_in)
      @retry_in = retry_in.to_i.clamp(1, 3600)
      super("Please wait #{SecurityCode.wait_words(@retry_in)} before asking for another code.")
    end
  end

  def self.wait_words(seconds)
    seconds < 90 ? "#{seconds} seconds" : "#{(seconds / 60.0).ceil} minutes"
  end

  def self.digest(value)
    OpenSSL::HMAC.hexdigest("SHA256", hmac_key, value.to_s)
  end

  def self.hmac_key = @hmac_key ||= Rails.application.key_generator.generate_key("brethreign security codes v1", 32)

  def self.code_digest(user, purpose, code) = digest("#{user.id}:#{purpose}:#{code}")

  # A fresh code (and one-tap link token when link: true). Raises RateLimited.
  def self.issue!(user:, purpose:, email: user.email, ip: nil, link: false)
    purpose = purpose.to_s
    check_send_limits!(user, purpose, ip)
    code = format("%06d", SecureRandom.random_number(1_000_000))
    token = link ? SecureRandom.urlsafe_base64(32) : nil
    record = create!(user: user, purpose: purpose, email: email.to_s.downcase.strip, ip: ip,
                     code_digest: code_digest(user, purpose, code), link_digest: token && digest(token),
                     expires_at: TTL.from_now)
    Issued.new(record, code, token)
  end

  # Seconds until another code may be sent (0 = now).
  def self.cooldown_for(user, purpose)
    last = where(user: user, purpose: purpose.to_s).maximum(:created_at)
    return 0 unless last

    [ (last + RESEND_COOLDOWN - Time.current).ceil, 0 ].max
  end

  def self.check_send_limits!(user, purpose, ip)
    wait = cooldown_for(user, purpose)
    raise RateLimited, wait if wait.positive?

    recent = where(user: user, purpose: purpose).where(created_at: 1.hour.ago..)
    if recent.count >= MAX_SENDS_PER_HOUR
      raise RateLimited, (recent.minimum(:created_at) + 1.hour - Time.current)
    end
    return if ip.blank?

    by_ip = where(ip: ip).where(created_at: 1.hour.ago..)
    raise RateLimited, (by_ip.minimum(:created_at) + 1.hour - Time.current) if by_ip.count >= MAX_SENDS_PER_IP_HOUR
  end

  # Checks a typed code against the member's live codes for this purpose (a
  # resend doesn't kill the previous code, so a slow first email still works).
  # A wrong guess counts against every live code.
  def self.check(user:, purpose:, code:, email: nil)
    purpose = purpose.to_s
    candidates = live.where(user: user, purpose: purpose)
    candidates = candidates.where(email: email.to_s.downcase.strip) if email
    candidates = candidates.order(created_at: :desc).to_a
    return Result.new(:expired, nil) if candidates.empty?

    typed = code.to_s.gsub(/\D/, "")
    wanted = typed.length == 6 ? code_digest(user, purpose, typed) : nil
    match = wanted && candidates.find { |c| ActiveSupport::SecurityUtils.secure_compare(c.code_digest, wanted) }
    if match
      return Result.new(:expired, nil) unless match.consume!

      where(user: user, purpose: purpose, consumed_at: nil).update_all(consumed_at: Time.current)
      Result.new(:ok, match)
    else
      where(id: candidates.map(&:id)).update_all("attempts = attempts + 1")
      left = MAX_ATTEMPTS - candidates.map { |c| c.attempts + 1 }.min
      Result.new(left.positive? ? :wrong : :too_many, nil)
    end
  end

  # The one-tap link from an email.
  def self.redeem_link(token)
    return nil if token.blank? || token.to_s.length > 100

    record = live.find_by(link_digest: digest(token))
    return nil unless record&.consume!

    where(user_id: record.user_id, purpose: record.purpose, consumed_at: nil).update_all(consumed_at: Time.current)
    record
  end

  # True for exactly one caller, even when two requests race.
  def consume!
    self.class.where(id: id, consumed_at: nil).update_all(consumed_at: Time.current) == 1
  end

  # Spent and expired codes are kept a day (for rate limits), then removed.
  def self.prune!
    where(created_at: ...1.day.ago).delete_all
  end
end

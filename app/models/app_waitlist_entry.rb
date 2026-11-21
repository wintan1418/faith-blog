# frozen_string_literal: true

# Someone who wants an email when the Brethreign iPhone / Android app is out
# ("Get the app" on the welcome page). One row per email, case-insensitive;
# signing up again with the same email just updates the platform.
#
# Nothing is emailed yet. When the apps launch, a mailer (say
# AppLaunchMailer.ready(entry)) can go through AppWaitlistEntry.for_platform.
class AppWaitlistEntry < ApplicationRecord
  PLATFORMS = %w[ios android both].freeze
  PLATFORM_NAMES = { "ios" => "iPhone", "android" => "Android", "both" => "both iPhone and Android" }.freeze
  # Stricter than type=email: a dot in the domain, no spaces.
  EMAIL_FORMAT = /\A[^@\s]+@[^@\s.]+(\.[^@\s.]+)+\z/

  normalizes :email, with: ->(email) { email.to_s.strip.downcase }
  normalizes :source, with: ->(source) { source.to_s.strip.first(40).presence }

  validates :email, presence: { message: "is needed so we can tell you." }
  validates :email, format: { with: EMAIL_FORMAT, message: "doesn't look right. Please check it." },
                    length: { maximum: 254 }, allow_blank: true
  validates :email, uniqueness: { case_sensitive: false }, allow_blank: true
  validates :platform, inclusion: { in: PLATFORMS, message: "should be iPhone, Android or both." }
  validate :email_not_disposable

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  # Who to tell when an app ships: "ios" → iPhone + both.
  scope :for_platform, ->(platform) { where(platform: [ platform.to_s, "both" ]) }

  # Adds the email, or updates the platform if it's already on the list.
  # Always returns the entry; check #persisted? / #errors.
  def self.join(email:, platform:, source: nil, remote_ip: nil)
    entry = find_or_initialize_by(email: normalize_value_for(:email, email))
    entry.platform = platform.to_s
    entry.source ||= source
    entry.ip_hash = hash_ip(remote_ip) if remote_ip.present?
    entry.save
    entry
  rescue ActiveRecord::RecordNotUnique
    # Two submits raced on the same new email: the other one won, so update it.
    retry
  end

  # Kept only to spot floods from one address, never the address itself.
  def self.hash_ip(ip)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "waitlist:#{ip}")
  end

  def self.platform_counts
    counts = group(:platform).count
    PLATFORMS.index_with { |p| counts.fetch(p, 0) }
  end

  def platform_name
    PLATFORM_NAMES.fetch(platform, "both iPhone and Android")
  end

  private

  def email_not_disposable
    return unless DisposableEmail.disposable?(email)

    errors.add(:email, "from a throwaway email service can't be used. Please use your personal email.")
  end
end

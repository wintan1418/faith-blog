# frozen_string_literal: true

# What happened to an account's security, and from where (approximate place
# and device only). Shown to admins (Admin → Users → Security) and used to
# limit guessing per IP. Recording never breaks the request.
class SecurityEvent < ApplicationRecord
  KINDS = %w[
    sign_in sign_in_challenged code_sent code_failed email_verified email_changed password_changed
    two_factor_enabled two_factor_disabled two_factor_failed recovery_code_used recovery_codes_regenerated
    device_signed_out signed_out_everywhere account_secured
    admin_resent_verification admin_reset_two_factor
  ].freeze

  LABELS = {
    "sign_in" => "Signed in", "sign_in_challenged" => "Asked for a sign-in code", "code_sent" => "Code sent",
    "code_failed" => "Wrong code", "email_verified" => "Email verified", "email_changed" => "Email changed",
    "password_changed" => "Password changed", "two_factor_enabled" => "Two-step login on",
    "two_factor_disabled" => "Two-step login off", "two_factor_failed" => "Wrong authenticator code",
    "recovery_code_used" => "Recovery code used", "recovery_codes_regenerated" => "New recovery codes",
    "device_signed_out" => "Device signed out", "signed_out_everywhere" => "Signed out everywhere else",
    "account_secured" => "\"Wasn't me\": account secured",
    "admin_resent_verification" => "Admin resent verification", "admin_reset_two_factor" => "Admin reset two-step login"
  }.freeze

  belongs_to :user, optional: true
  belongs_to :actor, class_name: "User", optional: true

  validates :kind, inclusion: { in: KINDS }

  scope :recent, -> { order(created_at: :desc) }
  scope :sign_ins, -> { where(kind: "sign_in") }

  def self.record!(kind, user:, request: nil, actor: nil, device_name: nil, location: nil, **metadata)
    info = request ? DeviceInfo.from(request) : nil
    create!(kind: kind.to_s, user: user, actor: actor, ip: request&.remote_ip,
            device_name: device_name || info&.name, location: location || info&.location,
            metadata: metadata.compact)
  rescue StandardError => e
    Rails.logger.warn("[SecurityEvent] #{kind} for user #{user&.id} not recorded: #{e.class}: #{e.message}")
    nil
  end

  # Guesses from one IP across every account (codes and authenticator codes).
  def self.failures_from_ip(ip, within: 15.minutes)
    return 0 if ip.blank?

    where(kind: %w[code_failed two_factor_failed], ip: ip).where(created_at: within.ago..).count
  end

  def label = LABELS.fetch(kind, kind.humanize)

  def self.prune!
    where(created_at: ...13.months.ago).delete_all
  end
end

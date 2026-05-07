# frozen_string_literal: true

# An admin-authored email blast to every user with email notifications
# enabled. The body is rich text (Trix) so an admin can format inline
# without writing HTML, but the mailer renders both an HTML and a
# plain-text version for clients that prefer it.
class Broadcast < ApplicationRecord
  enum :status, { draft: 0, sending: 1, sent: 2, failed: 3 }

  belongs_to :sender, class_name: "User"
  has_rich_text :body

  validates :subject, presence: true, length: { minimum: 3, maximum: 200 }
  validates :preheader, length: { maximum: 200 }, allow_blank: true
  validate  :body_must_be_present

  scope :recent, -> { order(created_at: :desc) }

  # Snapshot count of users who will receive this — for the admin UI
  # confirmation step ("send to 1,234 users?"). Lives in a method instead
  # of a column so it stays accurate as users sign up / opt out.
  def self.eligible_user_count
    User.where(active: true)
        .where(email_notifications_enabled: true)
        .where.not(email: [ nil, "" ])
        .count
  end

  # Hand-back a fresh draft pre-filled with the comprehensive launch copy
  # so an admin can click "New broadcast" and immediately have something
  # publishable to skim, edit, and send.
  def self.new_with_launch_template(sender:)
    new(
      sender: sender,
      subject: "Brethreign — what's new since you last visited",
      preheader: "Prayer chains, AI gentleness check, voice notes, and more.",
      body: BroadcastTemplates.launch_announcement_html
    )
  end

  private

  def body_must_be_present
    return if body.present? && body.to_plain_text.to_s.strip.length >= 20

    errors.add(:body, "needs at least a few sentences")
  end
end

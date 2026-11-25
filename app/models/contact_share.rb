# frozen_string_literal: true

# One connection a member chose to share their Brethren Card contact details
# with ("Connections I choose"). The owner can take it back at any time. If
# the two stop being connected, the share stops counting.
class ContactShare < ApplicationRecord
  belongs_to :owner, class_name: "User"
  belongs_to :viewer, class_name: "User"
  has_many :notifications, as: :notifiable, dependent: :destroy

  validates :viewer_id, uniqueness: { scope: :owner_id, message: "already has your contact details" }
  validate :not_self
  validate :not_blocked
  validate :connected, on: :create

  after_create_commit :notify_viewer

  private

  def not_self
    errors.add(:base, "That's you.") if owner_id.present? && owner_id == viewer_id
  end

  def connected
    return if owner.nil? || viewer.nil? || owner_id == viewer_id

    errors.add(:base, "You can share your contact details with your connections. Connect with #{viewer.display_name} first.") unless owner.connected_with?(viewer)
  end

  def not_blocked
    errors.add(:base, "You can't share your contact details with this member.") if MessageBlock.between?(owner_id, viewer_id)
  end

  # "Maria shared their contact details with you" (an alert and a push, no email).
  def notify_viewer
    Notification.create(user: viewer, actor: owner, notification_type: :contact_shared, notifiable: self)
  rescue StandardError => e
    Rails.logger.warn("[ContactShare##{id}] notification failed: #{e.class}: #{e.message}")
  end
end

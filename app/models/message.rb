# frozen_string_literal: true

class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :sender, class_name: "User"

  validates :body, presence: true, length: { maximum: 4_000 }
  validate :sender_is_participant

  scope :visible, -> { where(deleted_at: nil) }
  scope :oldest_first, -> { order(created_at: :asc) }

  after_create_commit :touch_conversation
  after_create_commit :notify_recipient

  def deleted?
    deleted_at.present?
  end

  private

  def sender_is_participant
    return if conversation&.conversation_participants&.exists?(user: sender)

    errors.add(:sender, "must be part of the conversation")
  end

  def touch_conversation
    conversation.update_column(:last_message_at, created_at)
  end

  def notify_recipient
    recipient = conversation.other_participant_for(sender)
    return unless recipient

    Notification.create(
      user: recipient,
      actor: sender,
      notifiable: self,
      notification_type: :direct_message
    )
  end
end

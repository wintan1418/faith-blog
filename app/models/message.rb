# frozen_string_literal: true

class Message < ApplicationRecord
  belongs_to :conversation
  belongs_to :sender, class_name: "User"
  has_many :reports, as: :reportable, dependent: :destroy

  validates :body, presence: true, length: { maximum: 4_000 }
  validate :sender_is_participant
  validate :sender_is_not_blocked

  scope :visible, -> { where(deleted_at: nil) }
  scope :oldest_first, -> { order(created_at: :asc) }

  after_create_commit :touch_conversation
  after_create_commit :broadcast_to_participants
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

  def sender_is_not_blocked
    return unless conversation && sender

    recipient = conversation&.other_participant_for(sender)
    return unless recipient && MessageBlock.between?(sender, recipient)

    errors.add(:base, "Messaging is blocked for this conversation")
  end

  def broadcast_to_participants
    conversation.conversation_participants.find_each do |participant|
      broadcast_append_later_to(
        [ conversation, participant.user_id, :messages ],
        target: "messages",
        partial: "conversations/message",
        locals: { message: self, viewer_id: participant.user_id }
      )
      broadcast_replace_later_to(
        [ conversation, participant.user_id, :read_receipt ],
        target: "read_receipt",
        partial: "conversations/read_receipt",
        locals: { conversation: conversation, viewer_id: participant.user_id }
      )
    end
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

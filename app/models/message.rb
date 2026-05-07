# frozen_string_literal: true

class Message < ApplicationRecord
  MAX_IMAGES = 4

  belongs_to :conversation
  belongs_to :sender, class_name: "User"
  has_many :reports, as: :reportable, dependent: :destroy
  has_many :likes, as: :likeable, dependent: :destroy

  has_many_attached :images
  has_one_attached  :voice_note

  def edited?
    edited_at.present?
  end

  # Body is optional when the message carries an image or a voice note.
  # When neither attachment is present, body must be there.
  validates :body, length: { maximum: 4_000 }, presence: true, unless: :has_attachments?
  validates :body, length: { maximum: 4_000 }, allow_blank: true
  validate  :sender_is_participant
  validate  :sender_is_not_blocked
  validate  :max_images_count

  def has_attachments?
    (images.respond_to?(:attached?) && images.attached?) ||
      (voice_note.respond_to?(:attached?) && voice_note.attached?)
  end

  def has_images?
    images.attached? && images.any?
  end

  def has_voice_note?
    voice_note.attached?
  end

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

  def max_images_count
    return unless images.attached?
    return if images.count <= MAX_IMAGES

    errors.add(:images, "cannot exceed #{MAX_IMAGES} images per message")
  end

  def broadcast_to_participants
    conversation.conversation_participants.find_each do |participant|
      # Sender already saw the message echoed back through the
      # create.turbo_stream response — skip them to avoid duplicates.
      next if participant.user_id == sender_id

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

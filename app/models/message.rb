# frozen_string_literal: true

class Message < ApplicationRecord
  include AttachmentValidatable

  MAX_IMAGES = 4
  IMAGE_MAX_BYTES = 10.megabytes
  VOICE_MAX_BYTES = 6.megabytes

  belongs_to :conversation
  belongs_to :sender, class_name: "User"
  has_many :reports, as: :reportable, dependent: :destroy
  has_many :likes, as: :likeable, dependent: :destroy

  has_many_attached :images
  has_one_attached  :voice_note

  def edited?
    edited_at.present?
  end

  # Body is optional when the message carries an image, a voice note, or a
  # shared scripture. When none of those are present, body must be there.
  before_validation :normalize_scripture_ref
  # body is NOT NULL at the DB level; a message carried only by an image,
  # voice note, or verse still needs an empty string rather than nil.
  before_validation { self.body = body.to_s }

  validates :body, presence: true, unless: :body_optional?
  validates :body, length: { maximum: 4_000 }, allow_blank: true
  validates :scripture_ref, length: { maximum: 120 }, allow_blank: true
  validate  :sender_is_participant
  validate  :sender_is_not_blocked
  validate  :max_images_count
  validate  :attachments_content_type_and_size
  validate  :scripture_ref_looks_like_a_reference

  def attachments_content_type_and_size
    validate_image_attachment(:images, max_bytes: IMAGE_MAX_BYTES)
    validate_audio_attachment(:voice_note, max_bytes: VOICE_MAX_BYTES)
  end

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

  def has_scripture?
    scripture_ref.present?
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

  # A body isn't required when the message already carries something to say:
  # an image, a voice note, or a shared verse.
  def body_optional?
    has_attachments? || scripture_ref.present?
  end

  # Accept free-form input like "read John 3:16 today" and keep just the
  # reference. Blank stays blank; unrecognised text is left as-is so the
  # validation below can reject it.
  def normalize_scripture_ref
    return if scripture_ref.blank?

    detected = ScriptureLookup.find_references(scripture_ref).first
    self.scripture_ref = (detected || scripture_ref).to_s.strip
  end

  def scripture_ref_looks_like_a_reference
    return if scripture_ref.blank?
    return if ScriptureLookup.find_references(scripture_ref).present?

    errors.add(:scripture_ref, "should look like a verse reference, e.g. John 3:16")
  end

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

      # Broadcast synchronously (not the _later variants) so delivery never
      # waits on a Solid Queue worker — otherwise a message doesn't reach the
      # open conversation until the recipient re-renders the thread. Typing
      # indicators already push over the cable directly; messages now match.
      broadcast_append_to(
        [ conversation, participant.user_id, :messages ],
        target: "messages",
        partial: "conversations/message",
        locals: { message: self, viewer_id: participant.user_id }
      )
      broadcast_replace_to(
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

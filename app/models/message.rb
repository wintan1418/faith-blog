# frozen_string_literal: true

class Message < ApplicationRecord
  include AttachmentValidatable

  MAX_IMAGES = 4
  IMAGE_MAX_BYTES = 10.megabytes
  VOICE_MAX_BYTES = 6.megabytes

  belongs_to :conversation
  belongs_to :sender, class_name: "User"
  # The message this one replies to (shown as a quote above it).
  belongs_to :reply_to, class_name: "Message", optional: true
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
  validate  :reply_to_same_conversation
  validate  :sender_is_not_blocked
  validate  :max_images_count
  validate  :attachments_content_type_and_size
  validate  :scripture_ref_looks_like_a_reference
  # No offensive language in messages (instant, before saving; see CleanLanguage).
  validate :language_is_clean, if: :will_save_change_to_body?

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

  # A short line describing this message, for the quote shown above a reply.
  def quote_snippet(length = 90)
    return "This message was deleted" if deleted?
    return "This message was removed" if removed?
    return body.to_s.squish.truncate(length) if body.present?
    return "📷 Photo" if has_images?
    return "🎤 Voice note" if has_voice_note?
    return "📖 #{scripture_ref}" if has_scripture?

    "Message"
  end

  def has_scripture?
    scripture_ref.present?
  end

  scope :visible, -> { where(deleted_at: nil) }
  scope :oldest_first, -> { order(created_at: :asc) }

  after_create_commit :touch_conversation
  after_create_commit :broadcast_to_participants
  # AI review first; it notifies the recipient once the message is cleared.
  after_create_commit :moderate

  # The message just before this one in its thread (for grouping and day dividers).
  def previous_in_thread
    conversation.messages.visible.where(created_at: ...created_at).order(created_at: :desc).first
  end

  def language_is_clean
    errors.add(:base, CleanLanguage::MESSAGE) if CleanLanguage.offensive?(body)
  end

  # Removed by moderation: the text stays for the review queue, participants see a notice.
  def removed? = removed_at.present?

  def remove_for_moderation!
    update_columns(removed_at: Time.current)
    rebroadcast
  end

  def restore_after_review!
    update_columns(removed_at: nil)
    rebroadcast
    notify_recipient
  end

  # Redraw this message in both people's open chats.
  def rebroadcast
    conversation.conversation_participants.find_each do |participant|
      broadcast_replace_to [ conversation, participant.user_id, :messages ],
                           target: ActionView::RecordIdentifier.dom_id(self),
                           partial: "conversations/message",
                           locals: { message: self, viewer_id: participant.user_id }
    end
  rescue StandardError => e
    Rails.logger.warn("[Message##{id}] rebroadcast failed: #{e.class}: #{e.message}")
  end

  def notify_recipient
    recipient = conversation.other_participant_for(sender)
    return unless recipient

    # One unread chat notification per conversation: a burst of messages updates
    # it (and re-sends the phone notification, which replaces the last one)
    # instead of piling up a new notification for every line.
    waiting = recipient.notifications.unread.direct_message
                       .where(notifiable_type: "Message", notifiable_id: conversation.messages.select(:id))
                       .order(created_at: :desc).first
    if waiting
      waiting.update!(notifiable: self, actor: sender, created_at: Time.current)
      waiting.deliver_push_notification
    else
      Notification.create(user: recipient, actor: sender, notifiable: self, notification_type: :direct_message)
    end
  end

  def moderate
    if body.blank? && !has_images?
      notify_recipient # voice note only: nothing to read or look at
    elsif Ai::Moderation::Client.stub?
      MessageModerationJob.perform_now(self) # offline/test moderation decides right away
    else
      MessageModerationJob.perform_later(self)
    end
  rescue StandardError => e
    Rails.logger.warn("[Message##{id}] moderation enqueue failed, notifying anyway: #{e.class}: #{e.message}")
    notify_recipient
  end

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

  def reply_to_same_conversation
    return if reply_to.nil? || reply_to.conversation_id == conversation_id

    errors.add(:reply_to, "must be a message in this chat")
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

      begin
        # Broadcast synchronously (not the _later variants) so delivery never
        # waits on a Solid Queue worker — otherwise a message doesn't reach the
        # open conversation until the recipient re-renders the thread.
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
      rescue StandardError => e
        # A cable-layer failure (e.g. a misconfigured Solid Cable database)
        # must NEVER break sending the message. The message is already saved;
        # the recipient still sees it when the thread re-renders. Log and move on.
        Rails.logger.error(
          "[Message##{id}] broadcast to user #{participant.user_id} failed: #{e.class}: #{e.message}"
        )
      end
    end
  end
end

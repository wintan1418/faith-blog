# frozen_string_literal: true

# Private messages are private. The AI reads a message's words only when they
# come from someone the recipient isn't connected with, and only their first
# few messages (where scams and grooming start). Photos are always checked for
# nudity. Reported messages go to the moderators as before.
#
# Only the narrow list in Ai::Moderation::Leniency is removed automatically
# (sexual content, child safety, credible threats, clear scams); anything else
# the AI doubts is delivered and flagged for a moderator.
class MessageModerationJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  STRANGER_MESSAGES_CHECKED = 5 # a stranger's first messages in a chat

  # notify: false when re-checking an edit (the recipient was told already).
  def perform(message, notify: true)
    return if message.deleted? || message.moderated_at.present?

    result = review(message)
    verdict = decide(result)
    message.update_columns(moderated_at: Time.current)

    case verdict
    when :remove
      record(message, result, :flagged) # shows in the queue; a moderator can restore it
      message.remove_for_moderation!
    when :flag
      record(message, result, :flagged)
      message.notify_recipient if notify
    else
      message.notify_recipient if notify
    end
  rescue StandardError => e
    # Fail open: a moderation outage must never swallow people's messages.
    Rails.logger.warn("[MessageModerationJob] fail-open for message #{message&.id}: #{e.class}: #{e.message}")
    message&.notify_recipient if notify && !message&.removed?
  end

  private

  def review(message)
    text = if message.body.present? && words_checked?(message)
      Ai::Moderation::Reviewer.call(content: content_for(message), kind: "message", author_context: context_for(message))
    end
    pictures = (ImageModeration.review(message.images.attachments, kind: "message") if message.has_images?)
    ImageModeration.worse(text, pictures) || Ai::Moderation::Result.new(safe: true, severity: "none", categories: [],
                                                                       score: 0.0, summary: "", recommended_action: "allow")
  end

  # The sender's last few messages in this chat, so a scam or grooming pattern is visible.
  def content_for(message)
    earlier = message.conversation.messages.visible.where(sender_id: message.sender_id)
                     .where(created_at: ...message.created_at).order(created_at: :desc).limit(4).pluck(:body).reverse
    lines = earlier.compact_blank.map { |b| "(earlier) #{b}" }
    lines << "(new) #{message.body}"
    lines << "(new) [shared verse: #{message.scripture_ref}]" if message.scripture_ref.present?
    lines.join("\n")
  end

  def context_for(message)
    sender = message.sender
    return unless sender

    "account_age_days=#{((Time.current - sender.created_at) / 1.day).to_i} " \
      "connected_to_recipient=#{message.conversation.participants_connected?}"
  end

  # Between connected brethren, and after a stranger's first few messages, the
  # words aren't read at all.
  def words_checked?(message)
    return false if message.conversation.participants_connected?
    message.conversation.messages.where(sender_id: message.sender_id).where(id: ..message.id).count <= STRANGER_MESSAGES_CHECKED
  end

  def decide(result)
    return :remove if Ai::Moderation::Leniency.remove?(result)
    return :flag if Ai::Moderation::Leniency.flag?(result)

    :allow
  end

  def record(message, result, status)
    AiModerationReview.from_result(reviewable: message, user: message.sender, result: result, status: status).save!
  rescue StandardError => e
    Rails.logger.warn("[MessageModerationJob] couldn't record review: #{e.class}: #{e.message}")
  end
end

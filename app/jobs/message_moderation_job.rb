# frozen_string_literal: true

# AI review of a direct message, seconds after it's sent. Brethreign fights
# sexual content, occult practice and fraud hardest, so those are removed at once
# (for both people) and sent to the moderators' queue; anything else unsafe is
# flagged for a moderator. The recipient is notified only after the check, so a
# removed message never pops up on their phone.
class MessageModerationJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  REMOVE_CATEGORIES = %w[explicit_adult sexual_exploitation occult scam predatory_fundraising harassment hate].freeze

  def perform(message)
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
      message.notify_recipient
    else
      message.notify_recipient
    end
  rescue StandardError => e
    # Fail open: a moderation outage must never swallow people's messages.
    Rails.logger.warn("[MessageModerationJob] fail-open for message #{message&.id}: #{e.class}: #{e.message}")
    message&.notify_recipient unless message&.removed?
  end

  private

  def review(message)
    text = if message.body.present?
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

  def decide(result)
    return :allow if result.safe && result.severity.in?(%w[none low])

    categories = Array(result.categories).map(&:to_s)
    return :remove if result.recommended_action == "block"
    return :remove if result.severity == "high"
    return :remove if result.severity == "medium" && (categories & REMOVE_CATEGORIES).any?
    # Insults aimed at someone are removed even when the AI calls them mild.
    return :remove if (categories & %w[harassment hate]).any?

    :flag
  end

  def record(message, result, status)
    AiModerationReview.from_result(reviewable: message, user: message.sender, result: result, status: status).save!
  rescue StandardError => e
    Rails.logger.warn("[MessageModerationJob] couldn't record review: #{e.class}: #{e.message}")
  end
end

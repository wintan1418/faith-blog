# frozen_string_literal: true

# AI look at a portfolio piece: its words and up to four photos. If it's
# sexual, occult, hateful, gory or a scam it's hidden from the profile, the
# owner is told why, and it goes to the moderators' queue. Fails open, like
# the other moderation jobs. A hidden piece that passes after an edit shows again.
class PortfolioModerationJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  HIDE_CATEGORIES = %w[explicit_adult sexual_exploitation occult harassment hate scam fraud].freeze

  def perform(item)
    result = review(item)
    if result.nil? || (result.safe && result.severity.in?(%w[none low]))
      item.update_columns(hidden_at: nil) if item.hidden? # fixed after an edit: show it again
      return
    end

    hide = result.recommended_action.in?(%w[hide_pending_review block]) || result.severity == "high" ||
           (result.severity == "medium" && (Array(result.categories).map(&:to_s) & HIDE_CATEGORIES).any?)
    if hide
      item.update_columns(hidden_at: Time.current)
      Notification.create(user: item.user, notifiable: item, notification_type: :content_removed)
    end
    AiModerationReview.from_result(reviewable: item, user: item.user, result: result, status: :flagged).save!
  rescue StandardError => e
    Rails.logger.warn("[PortfolioModerationJob] skipped item #{item&.id}: #{e.class}: #{e.message}")
  end

  private

  def review(item)
    words = [ item.title, item.summary, item.contribution, item.description, item.link_url ].compact_blank.join("\n")
    text = Ai::Moderation::Reviewer.call(content: words, kind: "portfolio item") if words.present?
    pictures = (ImageModeration.review(item.images.attachments, kind: "portfolio") if item.images.attached?)
    ImageModeration.worse(text, pictures)
  end
end

# frozen_string_literal: true

class AiModerationReviewJob < ApplicationJob
  queue_as :default

  retry_on Ai::Moderation::Client::ApiError, wait: :polynomially_longer, attempts: 3
  retry_on Ai::Moderation::Reviewer::ParseError, wait: 30.seconds, attempts: 2
  discard_on ActiveJob::DeserializationError

  def perform(reviewable)
    return unless reviewable

    content = extract_content(reviewable)
    return if content.blank?

    user = reviewable.respond_to?(:user) ? reviewable.user : nil

    result = Ai::Moderation::Reviewer.call(
      content: content,
      kind: reviewable.class.name.underscore,
      author_context: author_context(user)
    )

    AiModerationReview.from_result(reviewable: reviewable, user: user, result: result)
    Ai::Moderation::RiskScorer.call(user: user) if user
  end

  private

  def extract_content(reviewable)
    case reviewable
    when Post
      [ reviewable.title, reviewable.content.to_s ].reject(&:blank?).join("\n\n")
    when Comment
      reviewable.content.to_s
    else
      reviewable.try(:body).to_s
    end
  end

  def author_context(user)
    return nil unless user

    parts = []
    parts << "account_age_days=#{((Time.current - user.created_at) / 1.day).to_i}"
    parts << "risk_level=#{user.risk_profile&.risk_level || "clear"}"
    parts.join(" ")
  end
end

# frozen_string_literal: true

# Async AI moderation gate for posts. Publish-first: the breath is live the
# moment it's created, and this job classifies it in the background —
# retro-holding or blocking only when the AI flags something. The feed must
# never depend on this job having run.
class AiModerationGateJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(post_id)
    post = Post.find_by(id: post_id)
    return unless post
    return unless post.published?
    # Act only while the post awaits its FIRST decision: no review row yet, or
    # still held with the review pending. Any settled review (cleared/flagged/
    # actioned/dismissed) means the AI or a moderator already decided — never
    # re-litigate a released or resolved breath.
    review = post.ai_moderation_review
    return if review.present? && !review.pending?

    # PostGatekeeper is fail-open: any AI/network error returns an :allow verdict
    # with no result, so a flaky upstream releases the post rather than wedging it.
    verdict = Ai::Moderation::PostGatekeeper.call(post: post)

    # The audit row must never block the decision — a validation failure here
    # used to raise before apply_moderation_decision!, leaving the post held
    # forever with no review row on the admin board.
    begin
      verdict.persist_review!(post)
    rescue StandardError => e
      Rails.logger.error("[AiModerationGateJob] persist_review failed for post #{post.id}: #{e.class}: #{e.message}")
    end

    post.apply_moderation_decision!(verdict.decision, reason: verdict.reason)
    Ai::Moderation::RiskScorer.call(user: post.user) if post.user

    notify_author(post, verdict) unless verdict.allow?
  end

  private

  def notify_author(post, verdict)
    Notification.create(
      user: post.user,
      actor: post.user,
      notifiable: post,
      notification_type: verdict.block? ? :post_blocked : :post_held_for_review
    )
  rescue StandardError => e
    Rails.logger.warn("[AiModerationGateJob] notify failed: #{e.class}: #{e.message}")
  end
end

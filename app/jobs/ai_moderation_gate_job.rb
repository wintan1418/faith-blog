# frozen_string_literal: true

# Async AI moderation gate for newly created posts. The post is saved as
# :pending_review (visible to its author, kept off the public feed) and this job
# runs the LLM classification off the request path, then approves / holds /
# blocks it. Replaces the old synchronous 12s-timeout gate that ran inside the
# create request.
class AiModerationGateJob < ApplicationJob
  queue_as :default

  discard_on ActiveJob::DeserializationError

  def perform(post_id)
    post = Post.find_by(id: post_id)
    return unless post
    # Only act while the post is still awaiting the async decision; a moderator
    # may have already resolved it by hand.
    return unless post.moderation_pending_review?

    # PostGatekeeper is fail-open: any AI/network error returns an :allow verdict
    # with no result, so a flaky upstream releases the post rather than wedging it.
    verdict = Ai::Moderation::PostGatekeeper.call(post: post)
    verdict.persist_review!(post)

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

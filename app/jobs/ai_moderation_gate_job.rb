# frozen_string_literal: true

# Async AI moderation gate for posts. Publish-first: the breath is live the
# moment it's created, and this job classifies it in the background —
# retro-holding or blocking only when the AI flags something. The feed must
# never depend on this job having run.
class AiModerationGateJob < ApplicationJob
  queue_as :moderation
  # The create hook and the backlog sweep can both enqueue the same post;
  # never classify one post twice at the same time.
  limits_concurrency to: 1, key: ->(post_id) { post_id }, duration: 5.minutes

  discard_on ActiveJob::DeserializationError

  # recheck: the author edited a breath that was already reviewed. The new
  # words/photos get the same look, but a recheck only ever tightens (holds or
  # blocks); it never releases a breath a moderator or earlier review stopped.
  def perform(post_id, recheck: false)
    post = Post.find_by(id: post_id)
    return unless post
    return unless post.published?
    return perform_recheck(post) if recheck

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

    notify_author(post, verdict) if verdict.block? # a flag alone never bothers the author
  end

  private

  def perform_recheck(post)
    verdict = Ai::Moderation::PostGatekeeper.call(post: post)
    return unless verdict.block? || verdict.hold? || verdict.flag?

    begin
      verdict.persist_review!(post)
    rescue StandardError => e
      Rails.logger.error("[AiModerationGateJob] recheck persist_review failed for post #{post.id}: #{e.class}: #{e.message}")
    end
    return unless verdict.block? || verdict.hold?
    return if post.moderation_blocked? # already as strict as it gets

    post.apply_moderation_decision!(verdict.decision, reason: verdict.reason)
    Ai::Moderation::RiskScorer.call(user: post.user) if post.user
    notify_author(post, verdict) if verdict.block?
  end

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

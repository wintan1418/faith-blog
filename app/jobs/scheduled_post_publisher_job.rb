# frozen_string_literal: true

# Sweeps scheduled posts whose scheduled_for has arrived and publishes them.
# Runs the moderation gatekeeper at publish time, so a post written hours
# earlier still gets classified by the same rules everyone else's posts do.
class ScheduledPostPublisherJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 100

  def perform
    Post.scheduled_due.find_each(batch_size: BATCH_SIZE) do |post|
      publish!(post)
    rescue StandardError => e
      Rails.logger.warn("[ScheduledPostPublisher] post=#{post.id} #{e.class}: #{e.message}")
    end
  end

  private

  def publish!(post)
    verdict = Ai::Moderation::PostGatekeeper.call(post: post)

    moderation_status =
      case verdict.decision
      when :block then Post.moderation_statuses[:blocked]
      when :hold  then Post.moderation_statuses[:pending_review]
      else             Post.moderation_statuses[:approved]
      end

    post.update_columns(
      status: Post.statuses[:published],
      moderation_status: moderation_status,
      moderation_blocked_reason: verdict.allow? ? nil : verdict.reason,
      published_at: Time.current
    )

    verdict.persist_review!(post)
    notify_author(post, verdict) unless verdict.allow?

    return unless verdict.allow?

    BreathFanoutJob.perform_later(post.id)
    post.user&.bump_breath_streak!
  end

  def notify_author(post, verdict)
    type = verdict.block? ? :post_blocked : :post_held_for_review
    Notification.create(
      user: post.user,
      actor: post.user,
      notifiable: post,
      notification_type: type
    )
  end
end

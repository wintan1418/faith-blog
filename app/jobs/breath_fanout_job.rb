# frozen_string_literal: true

# Notifies every follower of the post author when they publish a "breath".
class BreathFanoutJob < ApplicationJob
  queue_as :bulk

  BATCH_SIZE = 1000

  def perform(post_id)
    post = Post.find_by(id: post_id)
    # Defensive: never fan out a post that isn't publicly visible (held/blocked).
    return unless post && post.published? && post.moderation_approved? && post.user_id

    author = post.user
    follower_ids = author.followers.pluck(:id)
    return if follower_ids.empty?

    now = Time.current
    type = Notification.notification_types[:breath_from_followee]
    # One INSERT per 1000 followers instead of one giant statement.
    follower_ids.each_slice(BATCH_SIZE) do |ids|
      Notification.insert_all(ids.map do |follower_id|
        {
          user_id:           follower_id,
          actor_id:          author.id,
          notifiable_type:   "Post",
          notifiable_id:     post.id,
          notification_type: type,
          created_at:        now,
          updated_at:        now
        }
      end)
    end
  end
end

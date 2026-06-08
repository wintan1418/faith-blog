# frozen_string_literal: true

# Notifies every follower of the post author when they publish a "breath".
class BreathFanoutJob < ApplicationJob
  queue_as :default

  def perform(post_id)
    post = Post.find_by(id: post_id)
    # Defensive: never fan out a post that isn't publicly visible (held/blocked).
    return unless post && post.published? && post.moderation_approved? && post.user_id

    author = post.user
    follower_ids = author.followers.pluck(:id)
    return if follower_ids.empty?

    rows = follower_ids.map do |follower_id|
      {
        user_id:           follower_id,
        actor_id:          author.id,
        notifiable_type:   "Post",
        notifiable_id:     post.id,
        notification_type: Notification.notification_types[:breath_from_followee],
        created_at:        Time.current,
        updated_at:        Time.current
      }
    end

    Notification.insert_all(rows) if rows.any?
  end
end

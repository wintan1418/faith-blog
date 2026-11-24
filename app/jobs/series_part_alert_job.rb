# frozen_string_literal: true

# Tells a series' followers that a new part is up: an alert, with push and
# email the way other alerts go out. Queued a few minutes after the part
# joins, so an "Undo" right after publishing means nobody hears about it.
# Safe to run twice: a follower is told about a part once.
class SeriesPartAlertJob < ApplicationJob
  queue_as :default

  DELAY = 3.minutes

  def perform(post_id)
    post = Post.includes(:series, :room, :user).find_by(id: post_id)
    return unless post&.series && post.series_listable? && post.user&.active?

    told = Notification.where(notifiable: post, notification_type: :series_new_part).select(:user_id)
    post.series.series_follows.where.not(user_id: post.user_id).where.not(user_id: told)
        .includes(:user).find_each do |follow|
      next unless follow.user&.active?

      # Blocked pairs are refused by Notification's own validation.
      Notification.create(user: follow.user, actor: post.user, notifiable: post, notification_type: :series_new_part)
    end
  end
end

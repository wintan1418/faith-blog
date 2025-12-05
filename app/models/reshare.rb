# frozen_string_literal: true

class Reshare < ApplicationRecord
  belongs_to :user
  belongs_to :post, counter_cache: :reshares_count

  validates :user_id, uniqueness: { scope: :post_id, message: "has already reshared this post" }
  validate :cannot_reshare_own_post

  after_create :create_notification

  private

  def cannot_reshare_own_post
    errors.add(:base, "You cannot reshare your own post") if user_id == post.user_id
  end

  def create_notification
    return if post.user == user

    Notification.create(
      user: post.user,
      actor: user,
      notifiable: post,
      notification_type: :post_reshared
    )
  end
end

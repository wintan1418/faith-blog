# frozen_string_literal: true

class Reshare < ApplicationRecord
  belongs_to :user
  belongs_to :post, counter_cache: :reshares_count

  validates :user_id, uniqueness: { scope: :post_id, message: "has already reshared this post" }
  validates :thought, length: { maximum: 280 }, allow_blank: true
  validate :cannot_reshare_own_post

  after_create :create_notification

  def with_thought?
    thought.present?
  end

  private

  def cannot_reshare_own_post
    errors.add(:base, "You cannot reshare your own post") if user_id == post.user_id
  end

  def create_notification
    return if post.user == user

    notification = Notification.create(
      user: post.user,
      actor: user,
      notifiable: post,
      notification_type: :post_reshared
    )
    return if notification.persisted?

    Rails.logger.error(
      "[Reshare ##{id}] notification not created: #{notification.errors.full_messages.join(', ')}"
    )
  end
end

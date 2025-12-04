# frozen_string_literal: true

class Follow < ApplicationRecord
  # Associations
  belongs_to :follower, class_name: "User"
  belongs_to :following, class_name: "User"

  # Validations
  validates :follower_id, uniqueness: { scope: :following_id, message: "is already following this user" }
  validate :cannot_follow_self

  # Callbacks
  after_create :create_notification

  private

  def cannot_follow_self
    errors.add(:follower_id, "cannot follow yourself") if follower_id == following_id
  end

  def create_notification
    Notification.create(
      user: following,
      actor: follower,
      notifiable: self,
      notification_type: :new_follower
    )
  end
end


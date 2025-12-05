# frozen_string_literal: true

class Notification < ApplicationRecord
  # Enums
  enum :notification_type, {
    new_comment: 0,
    comment_reply: 1,
    new_follower: 2,
    post_featured: 3,
    new_post_in_room: 4,
    resource_approved: 5,
    resource_rejected: 6,
    mentioned: 7,
    post_liked: 8,
    comment_liked: 9,
    connection_request: 10,
    connection_accepted: 11,
    post_reshared: 12
  }

  # Associations
  belongs_to :user
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :notifiable, polymorphic: true

  # Validations
  validates :notification_type, presence: true

  # Scopes
  scope :unread, -> { where(read_at: nil) }
  scope :read, -> { where.not(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }
  scope :today, -> { where("created_at >= ?", Time.current.beginning_of_day) }

  # Instance methods
  def mark_as_read!
    update(read_at: Time.current) unless read?
  end

  def read?
    read_at.present?
  end

  def unread?
    !read?
  end

  def message
    case notification_type.to_sym
    when :new_comment
      "#{actor&.display_name || 'Someone'} commented on your post"
    when :comment_reply
      "#{actor&.display_name || 'Someone'} replied to your comment"
    when :new_follower
      "#{actor&.display_name || 'Someone'} started following you"
    when :post_featured
      "Your post has been featured!"
    when :new_post_in_room
      "New post in a room you follow"
    when :resource_approved
      "Your resource has been approved"
    when :resource_rejected
      "Your resource was not approved"
    when :mentioned
      "#{actor&.display_name || 'Someone'} mentioned you"
    when :post_liked
      "#{actor&.display_name || 'Someone'} reacted to your post"
    when :comment_liked
      "#{actor&.display_name || 'Someone'} reacted to your comment"
    when :connection_request
      "#{actor&.display_name || 'Someone'} wants to know you more"
    when :connection_accepted
      "#{actor&.display_name || 'Someone'} accepted your connection request"
    when :post_reshared
      "#{actor&.display_name || 'Someone'} reshared your post"
    else
      "You have a new notification"
    end
  end

  # Class methods
  def self.mark_all_as_read!(user)
    user.notifications.unread.update_all(read_at: Time.current)
  end
end


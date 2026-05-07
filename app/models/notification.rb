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
    post_reshared: 12,
    direct_message: 13,
    breath_from_followee: 14,
    everyone_mention:     15,
    prayer_joined:        16,
    prayer_answered:      17
  }

  # Associations
  belongs_to :user
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :notifiable, polymorphic: true

  # Validations
  validates :notification_type, presence: true

  after_create_commit :deliver_email_notification
  after_create_commit :deliver_push_notification

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
    when :direct_message
      "#{actor&.display_name || 'Someone'} sent you a message"
    when :breath_from_followee
      "#{actor&.display_name || 'Someone'} breathed"
    when :everyone_mention
      "#{actor&.display_name || 'Someone'} mentioned everyone"
    when :prayer_joined
      "#{actor&.display_name || 'Someone'} joined your prayer chain"
    when :prayer_answered
      "A prayer you joined was just marked answered 🌟"
    else
      "You have a new notification"
    end
  end

  def target_path
    case notification_type.to_sym
    when :new_comment, :comment_reply
      Rails.application.routes.url_helpers.post_path(notifiable.post)
    when :new_follower
      Rails.application.routes.url_helpers.user_path(actor.username)
    when :post_featured, :post_liked, :post_reshared, :mentioned, :breath_from_followee, :everyone_mention, :prayer_joined, :prayer_answered
      post = notifiable.respond_to?(:post) ? notifiable.post : notifiable
      Rails.application.routes.url_helpers.post_path(post)
    when :new_post_in_room
      room = notifiable.respond_to?(:room) ? notifiable.room : notifiable
      Rails.application.routes.url_helpers.room_path(room)
    when :resource_approved, :resource_rejected
      Rails.application.routes.url_helpers.resources_item_path(notifiable)
    when :connection_request, :connection_accepted
      Rails.application.routes.url_helpers.my_connections_path
    when :direct_message
      Rails.application.routes.url_helpers.conversation_path(notifiable.conversation)
    else
      Rails.application.routes.url_helpers.notifications_path
    end
  rescue StandardError
    Rails.application.routes.url_helpers.notifications_path
  end

  # Class methods
  def self.mark_all_as_read!(user)
    user.notifications.unread.update_all(read_at: Time.current)
  end

  private

  def deliver_email_notification
    return unless user.email_notifications_enabled?

    NotificationMailer.with(notification: self).community_notification.deliver_later
  end

  def deliver_push_notification
    return unless WebPushConfig.configured?
    return if user.push_subscriptions.none?

    PushNotificationJob.perform_later(self)
  end
end

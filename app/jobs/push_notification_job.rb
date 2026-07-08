# frozen_string_literal: true

class PushNotificationJob < ApplicationJob
  queue_as :default
  discard_on ActiveJob::DeserializationError

  def perform(notification)
    return unless notification
    return unless WebPushConfig.configured?

    user = notification.user
    return unless user
    subs = user.push_subscriptions
    return if subs.empty?

    payload = build_payload(notification)
    subs.find_each do |sub|
      sub.deliver(**payload)
    end
  end

  private

  def build_payload(notification)
    {
      title: "Brethreign",
      body:  notification.message,
      url:   notification.target_path,
      icon:  "/icon.png",
      tag:   push_tag(notification)
    }
  end

  # Collapse all messages in one conversation into a single, self-replacing
  # notification so a burst of DMs doesn't stack into a wall of alerts.
  def push_tag(notification)
    if notification.direct_message? && notification.notifiable.respond_to?(:conversation_id)
      "brethreign-dm-#{notification.notifiable.conversation_id}"
    else
      "brethreign-#{notification.notification_type}-#{notification.notifiable_id}"
    end
  end
end

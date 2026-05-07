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
      tag:   "brethreign-#{notification.notification_type}-#{notification.notifiable_id}"
    }
  end
end

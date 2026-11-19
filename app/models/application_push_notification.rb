# Push sent to the iOS / Android apps (see PushNotificationJob).
class ApplicationPushNotification < ActionPushNative::Notification
  queue_as :realtime
end

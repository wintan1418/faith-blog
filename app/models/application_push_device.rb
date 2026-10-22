# A phone running the iOS or Android app, registered for push notifications.
# Invalid or expired tokens are destroyed automatically by the gem.
class ApplicationPushDevice < ActionPushNative::Device
  scope :deliverable, -> { where(platform: NativePushConfig.configured_platforms) }
end

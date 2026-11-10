# frozen_string_literal: true

# Alerts (and a push) for members on an older Android app: "Brethreign 1.0.8 is out".
class AppUpdateReminderJob < ApplicationJob
  queue_as :default

  def perform(release_id)
    release = AppRelease.find_by(id: release_id)
    return unless release&.latest

    release.outdated_users.find_each do |user|
      next if user.notifications.app_update.where(created_at: 3.days.ago..).exists?

      Notification.create(user: user, notifiable: release, notification_type: :app_update)
    end
  end
end

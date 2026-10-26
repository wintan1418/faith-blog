# frozen_string_literal: true

# Every morning: tell each person's brethren (accepted connections) whose birthday it is.
class BirthdayNotificationsJob < ApplicationJob
  queue_as :default

  def perform(date = Profile.today_for_birthdays)
    Profile.birthday_on(date).where(show_birthday: true).includes(:user).find_each do |profile|
      celebrant = profile.user
      next unless celebrant

      User.where(id: celebrant.connection_ids).find_each do |friend|
        # Once per birthday, even if the job runs twice.
        next if friend.notifications.birthday.where(actor: celebrant, created_at: date.in_time_zone(Profile::BIRTHDAY_ZONE).all_day).exists?

        Notification.create(user: friend, actor: celebrant, notifiable: celebrant, notification_type: :birthday)
      end
    end
  end
end

# frozen_string_literal: true

# Every 15 minutes: "Have you read your Bible today?" for members whose
# reminder time has come in their own time zone and who haven't read yet.
# One a day at most (last_reminded_on is claimed before the alert is made),
# and nobody who hasn't been on Brethreign for 30 days.
class BibleReminderJob < ApplicationJob
  queue_as :bulk
  limits_concurrency to: 1, key: ->(*) { "bible-reminders" }, duration: 15.minutes

  INACTIVE_AFTER = 30.days
  BATCH = 500

  def perform(now = Time.current)
    BibleHabit.where(reminder_enabled: true).where(next_reminder_at: ..now)
              .includes(:user).find_each(batch_size: BATCH) do |habit|
      remind(habit, now)
    rescue StandardError => e
      Rails.logger.error("[bible_reminder] habit #{habit.id}: #{e.class}: #{e.message}")
    end
  end

  private

  def remind(habit, now)
    today = now.in_time_zone(habit.zone).to_date
    due_today = now.in_time_zone(habit.zone) >= today.in_time_zone(habit.zone) + habit.reminder_minute.minutes
    user = habit.user

    if due_today && wanted?(habit, user, today, now)
      # Claim today first: a second run (or a retry) finds it taken.
      claimed = BibleHabit.where(id: habit.id).where("last_reminded_on IS NULL OR last_reminded_on < ?", today)
                          .update_all(last_reminded_on: today)
      Notification.create(user: user, notifiable: habit, notification_type: :bible_reminder) if claimed == 1
    end

    habit.update_column(:next_reminder_at, habit.next_reminder_after(now))
  end

  def wanted?(habit, user, today, now)
    return false unless user&.active? && !user.site_monitor?
    return false if user.last_seen_at.nil? || user.last_seen_at < now - INACTIVE_AFTER
    return false if habit.last_read_on.present? && habit.last_read_on >= today
    return false if habit.last_reminded_on.present? && habit.last_reminded_on >= today
    return false if habit.plan_finished?

    true
  end
end

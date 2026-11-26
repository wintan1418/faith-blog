# frozen_string_literal: true

require "test_helper"

# The daily "Have you read your Bible today?" reminder: at the member's local
# time, only if they haven't read, at most once a day, never for members away
# for 30 days or who turned it off.
class BibleReminderJobTest < ActiveSupport::TestCase
  setup do
    @member = create_member("reminded", last_seen_at: 1.day.ago)
    @habit = BibleHabit.for(@member)
  end

  # 07:15 in Lagos on 25 November.
  def morning = Time.utc(2026, 11, 25, 6, 15)

  def due!
    @habit.update_columns(next_reminder_at: morning - 15.minutes)
  end

  test "reminds once when the local time has come, and schedules tomorrow" do
    due!
    assert_difference -> { @member.notifications.bible_reminder.count }, 1 do
      BibleReminderJob.perform_now(morning)
      BibleReminderJob.perform_now(morning + 15.minutes)
    end
    note = @member.notifications.bible_reminder.last
    assert_equal "Have you read your Bible today? Today: John 1.", note.web_message
    assert_equal "/scripture/john-1", note.target_path
    @habit.reload
    assert_equal Date.new(2026, 11, 25), @habit.last_reminded_on
    assert_equal Time.utc(2026, 11, 26, 6, 0), @habit.next_reminder_at
  end

  test "never more than one a day, even if the row is due again" do
    due!
    BibleReminderJob.perform_now(morning)
    @habit.update_columns(next_reminder_at: morning)
    assert_no_difference -> { Notification.count } do
      BibleReminderJob.perform_now(morning + 30.minutes)
    end
  end

  test "skips members who already read today" do
    travel_to(morning - 1.hour) { @habit.record_read!(source: "card") }
    due!
    assert_no_difference -> { Notification.count } do
      BibleReminderJob.perform_now(morning)
    end
    assert @habit.reload.next_reminder_at > morning
  end

  test "skips members away for 30 days, and those who turned it off" do
    due!
    @member.update_columns(last_seen_at: morning - 31.days)
    assert_no_difference(-> { Notification.count }) { BibleReminderJob.perform_now(morning) }

    other = create_member("reminder_off", last_seen_at: 1.hour.ago)
    habit = BibleHabit.for(other)
    habit.update!(reminder_enabled: false)
    habit.update_columns(next_reminder_at: morning - 1.hour) # stale, but switched off
    assert_no_difference(-> { Notification.count }) { BibleReminderJob.perform_now(morning) }
  end

  test "a row found before the local time only reschedules" do
    @habit.update_columns(next_reminder_at: morning - 2.days, reminder_minute: 9 * 60)
    assert_no_difference(-> { Notification.count }) { BibleReminderJob.perform_now(morning) }
    assert_equal Time.utc(2026, 11, 25, 8, 0), @habit.reload.next_reminder_at
  end
end

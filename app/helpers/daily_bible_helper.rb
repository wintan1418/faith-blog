# frozen_string_literal: true

module DailyBibleHelper
  # "12 brethren read today" — a count only, never who.
  def daily_bible_readers_text(count, read: false)
    others = read ? count.to_i - 1 : count.to_i
    if read
      others.positive? ? "You and #{pluralize(others, 'other brother or sister', plural: 'other brethren')} read today" : "You're the first of the brethren to read today"
    else
      count.to_i.zero? ? "Be the first of the brethren to read today" : "#{count == 1 ? '1 of the brethren' : "#{number_with_delimiter(count)} brethren"} read today"
    end
  end

  # The chapter a member read today, for "Share what stood out".
  def daily_bible_read_today_label(habit)
    slug = habit.user.bible_reading_days.where(read_on: habit.today).pick(:first_chapter)
    Scripture::Reference.from_slug(slug.to_s)&.to_s
  end

  def daily_bible_share_prefill(label)
    label.present? ? "What stood out to me in #{label} today: " : "What stood out to me in my Bible reading today: "
  end

  def daily_bible_streak_text(streak) = "#{streak}-day streak"

  # Reminder times on the sheet: every half hour from 5:00 to 22:00.
  def daily_bible_reminder_options(habit)
    times = (10..44).map { |half| format("%02d:%02d", half / 2, (half % 2) * 30) }
    times << habit.reminder_time_label unless times.include?(habit.reminder_time_label)
    times.sort.map { |t| [ Time.zone.parse(t).strftime("%-l:%M %P"), t ] }
  end
end

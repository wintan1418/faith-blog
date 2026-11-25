# frozen_string_literal: true

# A member's daily Bible reading: the plan they follow and how far along they
# are, their reading streak and their once-a-day reminder. Every date here is
# the member's own local date (time_zone, sent by their browser).
class BibleHabit < ApplicationRecord
  DEFAULT_ZONE = "Africa/Lagos"
  DEFAULT_REMINDER_MINUTE = 7 * 60
  BADGE_STREAKS = [ 7, 30, 100, 365 ].freeze
  # Reading a chapter page this long (seconds, while it's on screen) counts.
  DWELL_SECONDS = 60

  belongs_to :user
  has_many :notifications, as: :notifiable, dependent: :delete_all

  validates :plan_slug, inclusion: { in: ->(_) { DailyBible::Plan.slugs } }
  validates :time_zone, inclusion: { in: ->(_) { BibleHabit.zone_names } }
  validates :reminder_minute, numericality: { only_integer: true, in: 0...(24 * 60) }

  before_save :schedule_reminder, if: -> { new_record? || will_save_change_to_reminder_minute? || will_save_change_to_time_zone? || will_save_change_to_reminder_enabled? }

  # What one read did, for the response: whether it was the day's first
  # (streak and seeds) and whether it finished the plan's next portion.
  Result = Data.define(:first_today, :advanced, :portion)

  def self.for(user)
    habit = user.bible_habit
    habit = nil if habit&.destroyed?
    habit || user.create_bible_habit!
  rescue ActiveRecord::RecordNotUnique
    user.reload.bible_habit
  end

  def self.zone_names = @zone_names ||= TZInfo::Timezone.all_identifiers.to_set

  def self.valid_zone?(name) = zone_names.include?(name.to_s)

  # ── Dates ─────────────────────────────────────────────────────────

  def zone = ActiveSupport::TimeZone[time_zone] || ActiveSupport::TimeZone[DEFAULT_ZONE]
  def now = Time.current.in_time_zone(zone)
  def today = now.to_date

  # ── Plan ──────────────────────────────────────────────────────────

  def plan = DailyBible::Plan.find(plan_slug) || DailyBible::Plan.default
  def position = plan_positions[plan.slug].to_i
  def plan_finished? = plan.finished?(position)

  # The next unread portion (nil once a plan that doesn't repeat is done).
  def portion = plan.portion_at(position)

  # "Chapter 3 of 1,189" in the plan, counting repeats as a fresh run.
  def portion_number = plan.size.zero? ? 0 : (position % plan.size) + 1

  def progress_percent
    return 100 if plan_finished?

    ((position % plan.size) * 100.0 / plan.size).round
  end

  def switch_plan!(slug)
    return false unless DailyBible::Plan.find(slug)

    update!(plan_slug: slug)
  end

  # ── Reading ───────────────────────────────────────────────────────

  def read_today? = last_read_on.present? && last_read_on >= today

  # The streak as it stands today: it survives until the end of tomorrow.
  def streak
    return 0 if last_read_on.blank? || last_read_on < today - 1

    current_streak
  end

  # A member read: from the card (`chapter` nil, "I've read it" for today's
  # portion), the "I've read it" button on a chapter page, or a minute spent
  # on one (`source: "dwell"`).
  #
  # Any chapter counts toward reading today. Only the plan's next portion
  # moves the plan on: tapping "I've read it" on any of its chapters, or
  # staying on its last chapter (for a single-chapter day, that chapter).
  def record_read!(source:, chapter: nil)
    source = source.to_s
    raise ArgumentError, "unknown source #{source}" unless BibleReadingDay::SOURCES.include?(source)

    result = nil
    day_row = nil
    with_lock do
      date = today
      current = portion
      advance = current.present? && advances?(current, chapter, source)

      day_row = user.bible_reading_days.find_by(read_on: date)
      first_today = day_row.nil?
      day_row ||= user.bible_reading_days.create!(read_on: date, source: source, plan_slug: plan.slug,
                                                  first_chapter: (chapter || current&.first)&.slug)
      if advance
        day_row.increment!(:portions_completed)
        self.plan_positions = plan_positions.merge(plan.slug => position + 1)
      end
      bump_streak(date) if first_today
      save!
      result = Result.new(first_today: first_today, advanced: advance, portion: current)
    end

    after_first_read(day_row) if result.first_today
    result
  end

  # ── Praying ───────────────────────────────────────────────────────

  def prayed_today? = last_prayed_on.present? && last_prayed_on >= today

  # The chapter today's prayer comes from: the first one read today.
  def today_chapter
    slug = user.bible_reading_days.where(read_on: today).pick(:first_chapter)
    Scripture::Reference.from_slug(slug.to_s)&.chapter_reference
  end

  # "Amen" on the prayer after reading. Only once something was read today;
  # pays its small seeds once a day. Returns whether it counted.
  def record_prayer!
    day_row = user.bible_reading_days.find_by(read_on: today)
    return false unless day_row

    with_lock do
      day_row.update!(prayed_at: Time.current) if day_row.prayed_at.nil?
      update!(last_prayed_on: day_row.read_on)
    end
    Seeds.bible_prayed(day_row)
    true
  end

  # ── Reminders ─────────────────────────────────────────────────────

  def reminder_time_label = format("%02d:%02d", reminder_minute / 60, reminder_minute % 60)

  def reminder_time=(value)
    hours, minutes = value.to_s.split(":").map(&:to_i)
    self.reminder_minute = (hours.to_i.clamp(0, 23) * 60) + minutes.to_i.clamp(0, 59) if value.present?
  end

  # The next local reminder moment after `from`.
  def next_reminder_after(from = Time.current)
    local = from.in_time_zone(zone)
    moment = local.beginning_of_day + reminder_minute.minutes
    moment += 1.day if moment <= local
    moment.utc
  end

  def card_collapsed_today? = card_collapsed_on.present? && card_collapsed_on >= today
  def card_hidden_today? = card_hidden_on.present? && card_hidden_on >= today

  # Would a minute on `chapter` count for anything today?
  def dwell_counts?(chapter)
    return true unless read_today?

    current = portion
    current.present? && advances?(current, chapter, "dwell")
  end

  private

  def advances?(current, chapter, source)
    return source == "card" if chapter.nil?
    return false unless current.include?(chapter)

    source == "chapter" || current.single? || (current.last.book == chapter.book && current.last.chapter == chapter.chapter)
  end

  def bump_streak(date)
    return if last_read_on.present? && last_read_on >= date # moved time zones: today is already counted

    self.current_streak = last_read_on == date - 1 ? current_streak + 1 : 1
    self.longest_streak = [ longest_streak, current_streak ].max
    self.days_read += 1
    self.last_read_on = date
  end

  def after_first_read(day_row)
    Seeds.bible_read(day_row)
    BadgeCheckJob.perform_later(user_id) if BADGE_STREAKS.include?(current_streak)
    begin
      Rails.cache.delete([ "bible-readers", day_row.read_on.iso8601 ])
    rescue StandardError
      nil
    end
  end

  def schedule_reminder
    self.next_reminder_at = reminder_enabled? ? next_reminder_after : nil
  end
end

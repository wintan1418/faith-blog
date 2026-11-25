# frozen_string_literal: true

require "test_helper"

# "Have you read your Bible today?": plans, what counts as reading, streaks in
# the member's own time zone, seeds once a day and the streak badges.
class BibleHabitTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @member = create_member("bible_reader")
    @habit = BibleHabit.for(@member)
  end

  def chapter(slug) = Scripture::Reference.from_slug(slug)

  test "the default plan starts with John, then the rest of the New Testament, then the Old, and repeats" do
    plan = DailyBible::Plan.default
    assert_equal 1189, plan.size
    assert_equal "John 1", plan.portions.first.label
    assert_equal "John 21", plan.portions[20].label
    assert_equal "Matthew 1", plan.portions[21].label
    assert_equal "Genesis 1", plan.portions[260].label
    assert_equal "Malachi 4", plan.portions.last.label
    assert plan.repeats?
    assert_equal "John 1", plan.portion_at(1189).label
  end

  test "the other plans have the expected shape" do
    assert_equal 89, DailyBible::Plan.find("gospels-89").size
    assert_equal 260, DailyBible::Plan.find("new-testament-year").size
    year = DailyBible::Plan.find("bible-year")
    assert_equal 365, year.size
    assert_equal 1189, year.portions.sum { |p| p.chapters.size }
    assert year.portions.all? { |p| p.chapters.size.between?(3, 4) }
    assert_equal "Genesis 1–3", year.portions.first.label
    psalms = DailyBible::Plan.find("psalms-proverbs")
    assert_equal 150, psalms.size
    assert_equal "Psalm 1 · Proverbs 1", psalms.portions.first.label
    assert_equal "Psalm 32 · Proverbs 1", psalms.portions[31].label
    refute psalms.repeats?
    assert psalms.finished?(150)
  end

  test "a new habit starts on the default plan with a 7:00 reminder scheduled" do
    assert_equal "chapter-a-day", @habit.plan_slug
    assert_equal "John 1", @habit.portion.label
    assert @habit.reminder_enabled?
    assert_equal "07:00", @habit.reminder_time_label
    assert @habit.next_reminder_at.future?
  end

  test "I've read it on the card finishes today's portion; a second tap the same day reads ahead" do
    result = @habit.record_read!(source: "card")
    assert result.first_today
    assert result.advanced
    assert @habit.read_today?
    assert_equal "John 2", @habit.portion.label
    assert_equal 1, @habit.streak
    assert_equal 1, @member.bible_reading_days.count

    second = @habit.record_read!(source: "card")
    refute second.first_today
    assert_equal "John 3", @habit.portion.label
    assert_equal 1, @member.bible_reading_days.count
    assert_equal 2, @member.bible_reading_days.first.portions_completed
  end

  test "a chapter outside the plan counts for today but doesn't move the plan" do
    result = @habit.record_read!(source: "dwell", chapter: chapter("psalm-23"))
    assert result.first_today
    refute result.advanced
    assert @habit.read_today?
    assert_equal "John 1", @habit.portion.label
    assert_equal "psalm-23", @member.bible_reading_days.first.first_chapter
  end

  test "a multi-chapter day moves on by tapping on any of its chapters, or staying on the last" do
    @habit.switch_plan!("bible-year") # Genesis 1–3
    refute @habit.record_read!(source: "dwell", chapter: chapter("genesis-1")).advanced
    assert @habit.record_read!(source: "dwell", chapter: chapter("genesis-3")).advanced
    assert_equal "Genesis 4–6", @habit.portion.label
    assert @habit.record_read!(source: "chapter", chapter: chapter("genesis-4")).advanced
    assert_equal "Genesis 7–9", @habit.portion.label
  end

  test "switching plans keeps your place in each" do
    @habit.record_read!(source: "card")
    @habit.switch_plan!("gospels-89")
    assert_equal "Matthew 1", @habit.portion.label
    @habit.switch_plan!("chapter-a-day")
    assert_equal "John 2", @habit.portion.label
  end

  test "streaks count local days in a row; a missed day resets the streak but never the plan" do
    travel_to Time.zone.parse("2026-11-20 09:00") do
      @habit.record_read!(source: "card")
    end
    travel_to Time.zone.parse("2026-11-21 09:00") do
      @habit.reload.record_read!(source: "card")
      assert_equal 2, @habit.streak
    end
    travel_to Time.zone.parse("2026-11-22 20:00") do
      assert_equal 2, @habit.reload.streak, "still alive until the end of the next day"
    end
    travel_to Time.zone.parse("2026-11-24 09:00") do
      assert_equal 0, @habit.reload.streak
      assert_equal "John 3", @habit.portion.label, "missed days don't skip readings"
      @habit.record_read!(source: "card")
      assert_equal 1, @habit.streak
      assert_equal 2, @habit.longest_streak
      assert_equal 3, @habit.days_read
    end
  end

  test "today is the member's own date" do
    @habit.update!(time_zone: "America/Los_Angeles")
    travel_to Time.utc(2026, 11, 21, 3, 0) do # 19:00 on the 20th in Los Angeles
      @habit.record_read!(source: "card")
      assert_equal Date.new(2026, 11, 20), @member.bible_reading_days.first.read_on
    end
    travel_to Time.utc(2026, 11, 21, 18, 0) do # the 21st in Los Angeles
      refute @habit.reload.read_today?
      @habit.record_read!(source: "card")
      assert_equal 2, @habit.streak
    end
  end

  test "reading pays seeds once a day" do
    @habit.record_read!(source: "card")
    @habit.record_read!(source: "dwell", chapter: chapter("psalm-1"))
    assert_equal 1, @member.seed_events.where(kind: "bible_read").count
    assert_equal Seeds.points_for("bible_read"), @member.reload.seeds_total
  end

  test "a seven-day streak earns the badge" do
    @habit.update_columns(current_streak: 6, longest_streak: 6, last_read_on: @habit.today - 1)
    perform_enqueued_jobs(only: BadgeCheckJob) { @habit.record_read!(source: "card") }
    assert @member.user_badges.exists?(slug: "bible_7")
    refute @member.user_badges.exists?(slug: "bible_30")
    assert @member.notifications.badge_earned.exists?
  end

  test "the reminder is scheduled at the member's local time" do
    travel_to Time.utc(2026, 11, 25, 12, 0) do
      @habit.update!(time_zone: "Europe/London", reminder_time: "18:30")
      assert_equal Time.utc(2026, 11, 25, 18, 30), @habit.next_reminder_at
      @habit.update!(reminder_time: "06:00")
      assert_equal Time.utc(2026, 11, 26, 6, 0), @habit.next_reminder_at
      @habit.update!(reminder_enabled: false)
      assert_nil @habit.next_reminder_at
    end
  end

  test "rejects unknown plans and time zones" do
    refute @habit.update(plan_slug: "nope")
    refute @habit.reload.update(time_zone: "Mars/Olympus")
  end

  test "deleting the member removes their reading" do
    @habit.record_read!(source: "card")
    assert_difference [ -> { BibleHabit.count }, -> { BibleReadingDay.count } ], -1 do
      @member.destroy!
    end
  end
end

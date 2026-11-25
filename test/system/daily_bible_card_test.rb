# frozen_string_literal: true

require "application_system_test_case"

# The Daily Bible card in a real browser: pick a plan in the sheet, tick
# today off, watch the streak grow, pray the chapter's prayer and put the
# card away for the day.
class DailyBibleCardTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    @member = create_member("card_reader", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i,
                                           tour_completed_at: Time.current, onboarding_dismissed_at: Time.current)
    login_as @member, scope: :user
  end

  teardown { Warden.test_reset! }

  test "choose a plan, read, see the streak, pray, and hide the card until tomorrow" do
    habit = BibleHabit.for(@member)
    habit.update_columns(current_streak: 4, longest_streak: 4, last_read_on: habit.today - 1)

    visit feed_path
    within("#daily_bible_card") do
      assert_text "Have you read your Bible today?"
      assert_text "John 1"
      assert_text "4-day streak"
      click_on "Reading plan and reminder"
    end

    within("dialog.db-sheet[open]") do
      find("label.db-plan", text: "The Gospels in 89 days").click
      click_on "Save"
    end
    assert_selector "#daily_bible_card .db-passage-ref", text: "Matthew 1"
    assert_equal "gospels-89", habit.reload.plan_slug

    within("#daily_bible_card") { click_on "I've read it" }
    assert_selector "#daily_bible_card.is-done", text: "Read today"
    assert_selector "#daily_bible_card", text: "5-day streak"
    assert_selector "#daily_bible_card", text: "Next: Matthew 2"
    assert_selector ".seed-toast", text: "+#{Seeds.points_for('bible_read')} seeds", wait: 5
    assert_equal 5, habit.reload.current_streak

    # "Read your Bible, pray every day": the prayer opens straight away.
    within("dialog.db-prayer-sheet[open]") do
      assert_text(/Pray it · Matthew 1/i)
      assert_text "Lord, thank you for speaking through Matthew 1 today."
      click_on "Amen"
    end
    assert_selector "#daily_bible_card.is-done", text: "Read & prayed today"
    assert_no_selector "dialog[open]"
    assert habit.reload.prayed_today?

    within("#daily_bible_card") { click_on "Hide until tomorrow" }
    assert_no_selector ".db-card"
    visit feed_path
    assert_no_selector ".db-card"
  end
end

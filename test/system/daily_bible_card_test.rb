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
      assert_text "Lord, I have read Matthew 1"
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

  test "share what I read from a chapter: pick a verse, add a note, post, and follow the card back to the chapter" do
    ScriptureVerse.insert_all((1..5).map { |v| { translation: "kjv", book: 43, chapter: 1, verse: v, text: "John one verse #{v}." } })
    ChapterPrayer.create!(slug: "john-1", reference: "John 1", version: ChapterPrayer::VERSION,
                          burden: "John 1 calls us to worship Jesus as the Word made flesh and to walk in his light today.",
                          points: [ { "kind" => "praise", "text" => "Praise Jesus as the Word who was with God.", "reference" => "John 1:1" },
                                    { "kind" => "intercession", "text" => "Pray for those still walking in darkness.", "reference" => "John 1:5" },
                                    { "kind" => "application", "text" => "Point someone to Jesus today.", "reference" => "John 1:3" } ],
                          key_verses: [ "John 1:5" ], verses: [ "John 1:5" ], themes: [ "Word", "Light" ],
                          body: "Lord, I worship you as the Word. Amen.", generated_at: Time.current)

    visit scripture_page_path("john-1")
    within("#daily_bible_bar_end") { click_on "I've read it" }
    within("#daily_bible_bar_end") do
      assert_selector "li.db-point", count: 3
      find("a.db-point-ref", text: "John 1:5").click
    end
    assert_equal "#v5", page.evaluate_script("window.location.hash")

    within("#daily_bible_bar_end") { click_on "Share what I read" }
    within("dialog.db-share-sheet[open]") do
      assert_selector "select[name=verse]"
      assert_text "“John one verse 5.”"
      fill_in "note", with: "Light wins."
      click_on "Post to feed"
    end
    assert_selector "[data-testid=reading-card] .rc-verse", text: "John one verse 5."
    assert_selector "[data-testid=reading-card] .rc-note", text: "Light wins."
    assert_selector "[data-testid=reading-card] .rc-burden-text", text: /Word made flesh/

    find("a[data-testid=reading-card-read]").click
    assert_current_path scripture_page_path("john-1")
  end
end

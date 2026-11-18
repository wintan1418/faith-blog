# frozen_string_literal: true

require "test_helper"

# Trello: "Read Chapter" on the feed's daily scripture said "Couldn't find".
# The verses were entered as "— Mark 9:23", so the button asked the Bible for
# a book called "— Mark".
class DailyVerseReadChapterTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @me = create_member("verse_reader", tour_completed_at: Time.current, welcomed_at: Time.current)
    BibleVerse.update_all(active: false)
    @verse = BibleVerse.new(text: "placeholder", active: true)
    @verse.save!
    # As stored before this fix (save would now clean it).
    @verse.update_columns(text: "“If thou canst believe, all things are possible.”", reference: "— Mark 9:23")
    Rails.cache.clear
  end

  test "the Read chapter button opens the plain chapter" do
    sign_in @me
    get feed_path
    assert_response :success
    assert_select ".eg-today-read[data-reference=?]", "Mark 9"
    assert_select ".eg-today-ref", text: "Mark 9:23"
    assert_select ".eg-today-verse", text: "“If thou canst believe, all things are possible.”"
  end

  test "that chapter loads in the Bible" do
    sign_in @me
    get scripture_lookup_path(reference: "Mark 9"), headers: { "Accept" => "application/json" }
    assert_response :success
  end

  test "new verses are saved clean" do
    v = BibleVerse.create!(text: "“For we walk by faith, not by sight.”", reference: " — 2 Corinthians 5:7", active: false)
    assert_equal [ "For we walk by faith, not by sight.", "2 Corinthians 5:7" ], [ v.text, v.reference ]
    assert_equal "2 Corinthians 5", BibleVerse.chapter_of(v.reference)
  end
end

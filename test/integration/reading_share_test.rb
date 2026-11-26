# frozen_string_literal: true

require "test_helper"

# "Read your Bible, pray every day", shared: private notes per chapter, the
# "Share what I read" form, the reading card it posts (feed and post page,
# with "Read John 1" and "Start your daily reading"), its status-image data
# and its link preview.
class ReadingShareTest < ActionDispatch::IntegrationTest
  TURBO = { "Accept" => "text/vnd.turbo-stream.html, text/html" }.freeze
  BURDEN = "John 1 calls us to worship Jesus as the eternal Word made flesh, and to receive him as the light no darkness can put out."

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @member = create_member("reading_sharer", welcomed_at: Time.current, tour_completed_at: Time.current,
                                              onboarding_dismissed_at: Time.current)
    ScriptureVerse.insert_all((1..14).map { |v| { translation: "kjv", book: 43, chapter: 1, verse: v, text: "John one verse #{v}." } })
    ChapterPrayer.create!(slug: "john-1", reference: "John 1", version: ChapterPrayer::VERSION, burden: BURDEN,
                          points: [ { "kind" => "praise", "text" => "Praise Jesus, the Word.", "reference" => "John 1:1" } ],
                          key_verses: [ "John 1:14", "John 1:5" ], verses: [ "John 1:14", "John 1:5" ], themes: [ "The Word", "Light" ],
                          body: "Lord, I worship you. Amen.", generated_at: Time.current)
    habit = BibleHabit.for(@member)
    habit.update_columns(current_streak: 11, longest_streak: 11, last_read_on: habit.today - 1)
    habit.record_read!(source: "chapter", chapter: Scripture::Reference.parse("John 1"))
  end

  def share!(**params)
    post daily_bible_share_path, params: { chapter: "john-1", verse: "john-1-14", note: "", **params }
  end

  test "My notes are saved per chapter, private to the writer, and cleared when emptied" do
    sign_in @member
    get scripture_page_path("john-1")
    assert_select "details#chapter_notes:not([open]) textarea[name=body]"

    patch daily_bible_notes_path, params: { chapter: "john-1", body: "  The Word became flesh <b>and dwelt</b>.\r\nAmong us.  " }, headers: TURBO
    assert_select "turbo-stream[action=replace][target=chapter_notes]"
    assert_includes response.body, "Saved"
    note = ChapterNote.find_by!(user: @member, slug: "john-1")
    assert_equal "The Word became flesh <b>and dwelt</b>.\nAmong us.", note.body

    get scripture_page_path("john-1")
    assert_select "details#chapter_notes[open] textarea", text: /The Word became flesh <b>and dwelt<\/b>/

    other = create_member("other_reader")
    sign_in other
    get scripture_page_path("john-1")
    assert_select "details#chapter_notes textarea", text: ""
    assert_not_includes response.body, "The Word became flesh"

    sign_in @member
    patch daily_bible_notes_path, params: { chapter: "john-1", body: "   " }, headers: TURBO
    assert_includes response.body, "Cleared"
    refute ChapterNote.exists?(user: @member)
  end

  test "the share form offers the key verses, today's burden and my notes (only once written)" do
    sign_in @member
    get new_daily_bible_share_path(chapter: "john-1")
    assert_response :success
    assert_select "turbo-frame#reading_share_form_john-1 form[action=?][data-turbo-frame=_top]", daily_bible_share_path do
      assert_select "textarea[name=note]"
      assert_select "select[name=verse] optgroup[label=Suggested] option:first-child[value=john-1-14][selected]", text: /John 1:14/
      assert_select "select[name=verse] optgroup[label='Every verse'] option", count: 14
      assert_select "input[name=include_burden][checked][data-text=?]", BURDEN
      assert_select "input[name=include_notes]", count: 0
      assert_select "button[data-testid=reading-status-image]", text: /Status image/
      assert_select "button[type=submit]", text: /Post to feed/
    end
    form = css_select("form.db-share-form").first
    assert_equal "John 1", form["data-chapter"]
    assert_equal "12", form["data-streak"] # read today: 12 days in the Word
    assert_equal scripture_page_url("john-1"), form["data-link"]

    ChapterNote.write!(@member, Scripture::Reference.parse("John 1"), "Grace upon grace.")
    get new_daily_bible_share_path(chapter: "john-1")
    assert_select "input[name=include_notes]:not([checked])[data-text=?]", "Grace upon grace."
  end

  test "sharing posts a reading card with the verse, my words, the burden and my notes only when chosen" do
    ChapterNote.write!(@member, Scripture::Reference.parse("John 1"), "Grace upon grace.")
    sign_in @member
    assert_difference -> { Post.count }, 1 do
      share!(note: "The light shines in the darkness.\n\n<script>alert(1)</script>", include_burden: "1")
    end
    post_record = Post.order(:id).last
    assert_redirected_to post_path(post_record)
    assert post_record.published? && post_record.reading_reflection?
    data = post_record.reading_share
    assert_equal "john-1", data["chapter"]
    assert_equal "john-1-14", data["verse"]
    assert_equal "John one verse 14.", data["verse_text"]
    assert_equal BURDEN, data["burden"]
    assert_equal 12, data["streak"]
    assert data["has_note"]
    assert_nil data["notes"], "notes stay private unless ticked"

    follow_redirect!
    assert_select "[data-testid=reading-card]" do
      assert_select ".rc-kicker", text: /Read your Bible, pray every day/
      assert_select ".rc-title a[href=?]", scripture_page_path("john-1"), text: "John 1"
      assert_select ".rc-streak", text: /12 days in the Word/
      assert_select ".rc-verse p", text: "“John one verse 14.”"
      assert_select ".rc-verse cite a[href=?]", scripture_page_path("john-1", anchor: "v14"), text: "John 1:14"
      assert_select ".rc-note", text: /The light shines in the darkness/
      assert_select ".rc-note script", count: 0
      assert_select ".rc-burden-text", text: BURDEN
      assert_select ".rc-notes", count: 0
      assert_select "a.rc-btn-primary[href=?]", scripture_page_path("john-1"), text: /Read John 1/
      assert_select "a.rc-btn-quiet[href=?]", daily_bible_start_path, text: /Start your daily reading/
    end

    share!(include_notes: "1", include_burden: "0")
    second = Post.order(:id).last
    assert_equal "Grace upon grace.", second.reading_share["notes"]
    assert_nil second.reading_share["burden"]
    refute second.reading_share["has_note"]
    assert_equal "I read John 1 today.", second.content.to_plain_text

    get feed_path
    assert_select "article##{ActionView::RecordIdentifier.dom_id(second)} [data-testid=reading-card]" do
      assert_select ".rc-notes", text: /Grace upon grace/
      assert_select ".rc-note", count: 0
      assert_select "a[data-testid=reading-card-read][href=?]", scripture_page_path("john-1")
    end
  end

  test "the server never trusts what the form sends" do
    sign_in @member
    share!(verse: "romans-8-1")
    assert_nil Post.order(:id).last.reading_share["verse"], "a verse from another chapter is dropped"
    share!(verse: "john-1-99")
    assert_nil Post.order(:id).last.reading_share["verse"]

    assert_no_difference -> { Post.count } do
      post daily_bible_share_path, params: { chapter: "not-a-book-9" }
    end
    assert_response :unprocessable_entity
  end

  test "Start your daily reading opens the plan picker for members and sign-up for guests" do
    get daily_bible_start_path
    assert_redirected_to new_user_registration_path

    sign_in @member
    BibleHabit.for(@member).update!(card_hidden_on: BibleHabit.for(@member).today)
    get daily_bible_start_path
    assert_redirected_to feed_path(bible: "plans", anchor: "daily_bible_card")
    follow_redirect!
    assert_select "#daily_bible_card[data-daily-bible-open-sheet-value=true] dialog.db-sheet input[name=plan_slug]"
  end

  test "the status image data and the link preview draw the reading card and lead to the chapter" do
    sign_in @member
    share!(note: "Light in the dark.", include_burden: "1")
    shared = Post.order(:id).last

    get post_share_card_path(shared)
    assert_response :success
    json = response.parsed_body
    assert_equal scripture_page_url("john-1"), json["link"]
    assert_equal "example.com/scripture/john-1", json["link_label"]
    assert_equal "John 1", json.dig("reading", "chapter")
    assert_equal "John 1:14", json.dig("reading", "verse_label")
    assert_equal "John one verse 14.", json.dig("reading", "verse_text")
    assert_equal "Light in the dark.", json.dig("reading", "note")
    assert_equal BURDEN, json.dig("reading", "burden")
    assert_equal 12, json.dig("reading", "streak")
    assert json["qr"].present?

    card = PostOgCard.new(shared)
    assert_equal "Read your Bible, pray every day", card.send(:label)
    image = Vips::Image.new_from_buffer(card.render, "")
    assert_equal [ 1200, 630 ], [ image.width, image.height ]
  end
end

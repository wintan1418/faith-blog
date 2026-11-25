# frozen_string_literal: true

require "test_helper"

# "Have you read your Bible today?" across the site: the feed card and its
# states, the chapter-page bars, the settings sheet, reminder and privacy
# settings, the profile streak and the admin numbers.
class DailyBibleTest < ActionDispatch::IntegrationTest
  TURBO = { "Accept" => "text/vnd.turbo-stream.html, text/html" }.freeze

  setup do
    @member = create_member("daily_reader", welcomed_at: Time.current, tour_completed_at: Time.current,
                                            onboarding_dismissed_at: Time.current)
    rows = (1..3).flat_map { |v| [ { translation: "kjv", book: 43, chapter: 1, verse: v, text: "John one verse #{v}." },
                                   { translation: "kjv", book: 19, chapter: 23, verse: v, text: "Psalm verse #{v}." } ] }
    ScriptureVerse.insert_all(rows)
  end

  def habit = BibleHabit.for(@member).reload

  test "the feed shows today's reading with Read and I've read it" do
    sign_in @member
    get feed_path
    assert_response :success
    assert_select "#daily_bible_card.is-open" do
      assert_select ".db-title", text: "Have you read your Bible today?"
      assert_select ".db-passage-ref", text: "John 1"
      assert_select "a.db-btn-primary[href=?]", scripture_page_path("john-1"), text: "Read today's chapter"
      assert_select "form[action=?] button", daily_bible_read_path, text: "I've read it"
      assert_select ".db-foot", text: /Be the first of the brethren to read today/
      assert_select "dialog.db-sheet input[name=plan_slug]", count: DailyBible::Plan.all.size
    end
  end

  test "I've read it turns the card into the done state, with seeds, and other readers are counted, never named" do
    other = create_member("early_reader")
    BibleHabit.for(other).record_read!(source: "card")
    sign_in @member

    post daily_bible_read_path, params: { source: "card" }, headers: TURBO
    assert_response :success
    assert_match "turbo-stream", response.media_type
    assert_select "turbo-stream[action=replace][target=daily_bible_card]"
    assert_includes response.body, "Read today"
    assert_includes response.body, "You and 1 other brother or sister read today"
    assert_includes response.body, "Next: John 2"
    assert_includes response.body, "Share what stood out"
    assert_includes response.body, "What stood out to me in John 1 today"
    assert_not_includes response.body, "early_reader"
    assert_includes response.body, "+#{Seeds.points_for('bible_read')} seeds"
    assert habit.read_today?
  end

  test "fold the card, open it again, and put it away until tomorrow" do
    sign_in @member
    post daily_bible_card_path, params: { state: "collapsed" }, headers: TURBO
    assert_includes response.body, "is-folded"
    get feed_path
    assert_select "#daily_bible_card.is-folded .db-mini-text", text: /John 1/

    post daily_bible_card_path, params: { state: "open" }, headers: TURBO
    get feed_path
    assert_select "#daily_bible_card.is-open"

    post daily_bible_card_path, params: { state: "hidden" }, headers: TURBO
    get feed_path
    assert_select "#daily_bible_card[hidden]"
    assert_select ".db-card", count: 0
  end

  test "the settings sheet changes plan, reminder and streak display, and keeps the time zone" do
    sign_in @member
    patch daily_bible_path, params: { plan_slug: "psalms-proverbs", reminder_enabled: "0", reminder_time: "21:30",
                                      show_streak: "0", time_zone: "Europe/London" }, headers: TURBO
    assert_response :success
    assert_includes response.body, "Psalm 1 · Proverbs 1"
    h = habit
    assert_equal "psalms-proverbs", h.plan_slug
    refute h.reminder_enabled?
    assert_equal "21:30", h.reminder_time_label
    refute h.show_streak?
    assert_equal "Europe/London", h.time_zone

    patch daily_bible_path, params: { plan_slug: "made-up", time_zone: "Nowhere/Land" }
    assert_redirected_to feed_path
    assert_equal "psalms-proverbs", habit.plan_slug
    assert_equal "Europe/London", habit.time_zone
  end

  test "the browser's time zone is saved quietly" do
    sign_in @member
    post daily_bible_zone_path, params: { time_zone: "Asia/Tokyo" }
    assert_response :no_content
    assert_equal "Asia/Tokyo", habit.time_zone
  end

  test "today's chapter page: the reading bar with the one-minute timer, and a dwell finishes it" do
    sign_in @member
    get scripture_page_path("john-1")
    assert_select "#daily_bible_bar_top[data-controller=bible-dwell][data-bible-dwell-chapter-value=john-1]",
                  text: /Today's reading · John 1/
    assert_select "#daily_bible_bar_end form[action=?] button", daily_bible_read_path, text: "I've read it"

    post daily_bible_read_path, params: { source: "dwell", chapter: "john-1" }, headers: TURBO
    assert_select "turbo-stream[target=daily_bible_bar_top]"
    assert_select "turbo-stream[target=daily_bible_bar_end]"
    assert_includes response.body, "Next in your plan"
    assert_equal "John 2", habit.portion.label

    get scripture_page_path("john-1")
    assert_select "#daily_bible_bar_top.is-done"
    assert_select "#daily_bible_bar_top[data-controller]", count: 0, message: "no timer once there's nothing to count"
  end

  test "another chapter counts for today without moving the plan" do
    sign_in @member
    get scripture_page_path("psalm-23")
    assert_select "#daily_bible_bar_top", text: /Reading this chapter counts for today/
    post daily_bible_read_path, params: { source: "chapter", chapter: "psalm-23" }, headers: TURBO
    assert habit.read_today?
    assert_equal "John 1", habit.portion.label
  end

  test "a dwell needs a chapter" do
    sign_in @member
    post daily_bible_read_path, params: { source: "dwell" }, headers: TURBO
    assert_response :unprocessable_entity
    refute habit.read_today?
  end

  test "guests see a light invitation on chapter pages, and the read endpoints need an account" do
    get scripture_page_path("john-1")
    assert_select ".db-guest a[href=?]", new_user_registration_path, text: "Join free"
    assert_select "#daily_bible_bar_top", count: 0

    post daily_bible_read_path, params: { source: "card" }
    assert_redirected_to new_user_session_path
  end

  test "the profile shows the reading streak unless switched off in privacy settings" do
    h = BibleHabit.for(@member)
    h.update_columns(current_streak: 5, longest_streak: 5, last_read_on: h.today)
    get user_path(@member.username)
    assert_select ".profile-stat-bible", text: /5\s+days in the Word/

    sign_in @member
    patch settings_privacy_path, params: { profile: { public_profile: "1" }, bible: { show_streak: "0" } }
    refute habit.show_streak?
    get user_path(@member.username)
    assert_select ".profile-stat-bible", count: 0
  end

  test "notification settings have an off switch and a time for the reminder" do
    sign_in @member
    get edit_settings_notifications_path
    assert_select "#daily-bible-reminder input[type=checkbox][name=reminder_enabled][checked]"
    assert_select "#daily-bible-reminder select[name=reminder_time] option[selected][value='07:00']"

    patch daily_bible_path, params: { reminder_enabled: "0", reminder_time: "06:30" },
                            headers: { "Referer" => edit_settings_notifications_url }
    assert_redirected_to edit_settings_notifications_url
    refute habit.reminder_enabled?
    assert_nil habit.next_reminder_at
  end

  test "admin dashboard shows the Daily Bible numbers" do
    admin = create_member("bible_admin", role: :admin)
    BibleHabit.for(@member).record_read!(source: "card")
    sign_in admin
    get admin_root_path
    assert_response :success
    assert_select "section[aria-label='Daily Bible'] .adash-kpi", count: 5
  end

  test "after reading on the feed, Pray it opens with a prayer from the chapter; Amen marks it prayed" do
    ChapterPrayer.create!(slug: "john-1", reference: "John 1", verses: [ "John 1:4", "John 1:5" ], generated_at: Time.current,
                          body: "Lord Jesus, you are the Word who was with God in the beginning. I thank you that your light shines in my darkness. Help me to receive you today and to live as your child. Amen.")
    sign_in @member
    post daily_bible_read_path, params: { source: "card" }, headers: TURBO
    assert_includes response.body, 'data-daily-bible-open-prayer-value="true"'
    assert_includes response.body, "Pray it · John 1"
    assert_includes response.body, "your light shines in my darkness"
    assert_select "dialog.db-prayer-sheet .db-prayer-verses a[href=?]", scripture_page_path("john-1-4"), text: "John 1:4"
    assert_select "dialog.db-prayer-sheet button[data-composer-modal-mode-param=prayer]", text: /Share this prayer/

    post daily_bible_amen_path, params: { chapter: "john-1" }, headers: TURBO
    assert_includes response.body, "Read &amp; prayed today"
    assert habit.prayed_today?
    assert_equal 1, @member.seed_events.where(kind: "bible_prayed").count
    assert_not_includes response.body, 'data-daily-bible-open-prayer-value="true"'

    post daily_bible_amen_path, params: { chapter: "john-1" }, headers: TURBO
    assert_equal 1, @member.seed_events.where(kind: "bible_prayed").count, "seeds once a day"
  end

  test "the chapter page shows Pray it after reading, with the fallback until the prayer is written" do
    sign_in @member
    post daily_bible_read_path, params: { source: "chapter", chapter: "psalm-23" }, headers: TURBO
    assert_select "turbo-stream[target=daily_bible_bar_end] template .db-prayer", text: /Pray it · Psalm 23/
    get scripture_page_path("psalm-23")
    assert_select "#daily_bible_bar_end .db-prayer-text", text: /Lord, thank you for speaking through Psalm 23 today/
    assert_select "#daily_bible_bar_top", text: /A short prayer from this chapter is waiting at the end/
  end

  test "Amen does nothing before anything was read today" do
    sign_in @member
    post daily_bible_amen_path, headers: TURBO
    refute habit.prayed_today?
  end

  test "What's new can point to today's chapter and the app waitlist" do
    Announcement.create!(kind: :release, kicker: "What's new", title: "New in Brethreign · Daily Bible",
                         body: "📖 Read your Bible, pray every day — A chapter a day. [[bible_today]]\n📲 The app — Join the waitlist. [[waitlist]]")
    @member.update_columns(created_at: 1.day.ago)
    sign_in @member
    get edit_settings_notifications_path
    assert_select "dialog.wn .wn-action a[href=?][data-action='whats-new#markSeen']", scripture_page_path("john-1"), text: "Read today's chapter"
    assert_select "dialog.wn .wn-action a[href=?][data-action='whats-new#markSeen']", join_waitlist_path, text: "Join the app waitlist"
  end
end

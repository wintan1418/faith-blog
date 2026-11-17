# frozen_string_literal: true

require "test_helper"

# The Evergreen feed (Nov 2026): one Today strip before the composer, icons
# instead of emoji, Your walk + a short list of shortcuts on the left, at most
# a few cards on the right, and four equal actions on every post.
class EvergreenFeedTest < ActionDispatch::IntegrationTest
  EMOJI = /\p{Extended_Pictographic}/

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @me = create_member("eg_me", current_breath_streak: 4)
    @author = create_member("eg_author")
    @room = Room.create!(name: "Evergreen Room", description: "x", room_type: :general, is_public: true)
    @post = Post.create!(user: @author, room: @room, title: "A quiet morning", content: "Grace and peace.",
                         status: :published, moderation_status: :approved)
    sign_in @me
  end

  teardown { ENV.delete("AI_MODERATION_STUB") }

  test "the Today strip carries the date, the streak, the verse of the day and who is online" do
    BibleVerse.create!(text: "The LORD is my shepherd; I shall not want.", reference: "Psalm 23:1", active: true) if BibleVerse.none?
    get feed_path
    assert_response :success

    assert_select ".eg-today" do
      assert_select "h1.eg-today-date time[data-controller='local-time']"
      assert_select ".eg-today-streak", /4-day streak/
      assert_select "blockquote.eg-today-verse"
      assert_select ".eg-today-ref"
      assert_select "button.eg-today-read[data-action='click->bible-drawer#open click->bible-drawer#openChapter'][data-reference]"
      # Presence keeps refreshing itself, now from inside the strip.
      assert_select "turbo-frame#online_now[data-controller='frame-refresh']"
    end
    # The old date row, Daily Breath card and full online card are gone.
    assert_select ".fc-masthead", false
    assert_select ".fc-daily-prompt", false
  end

  test "the composer card opens the composer in each mode from icon chips" do
    get feed_path
    assert_select ".eg-composer button[data-action='click->composer-modal#open'][data-tour-anchor='composer']"
    assert_select ".eg-chips" do
      assert_select "button.eg-chip.is-prayer[data-action='click->composer-modal#openWith'][data-composer-modal-prefill-param] svg"
      assert_select "button.eg-chip.is-verse[data-action='click->composer-modal#openWith'] svg"
      assert_select "button.eg-chip.is-photo[data-action='click->composer-modal#open'] svg"
      assert_select "button.eg-chip.is-voice[data-action='click->composer-modal#open'] svg"
    end
    assert_select ".eg-chips", text: /Prayer\s+Verse\s+Photo\s+Voice/
  end

  test "the left column has Your walk, five shortcuts and the rest behind See more" do
    get feed_path
    assert_select ".eg-left .eg-walk", text: /Your walk/
    assert_select ".eg-left .eg-walk .eg-walk-value", /4 days/
    assert_select ".eg-left .eg-shortcuts > .eg-shortcut", 5
    assert_select ".eg-left .eg-shortcuts details.eg-more" do
      [ games_path, church_history_path, blog_path, user_path(@me.username), my_connections_path, notifications_path ].each do |path|
        assert_select "a[href=?]", path
      end
    end
    assert_select ".eg-left .eg-rooms a[href=?]", rooms_path, text: "See all"
  end

  test "the right column has no emoji buttons and keeps its features reachable" do
    get feed_path
    assert_select ".fc-discover-quicklink-emoji", false
    assert_select ".eg-right .eg-pray-card", text: /Pray for the brethren/
    assert_select ".eg-right a[href=?]", games_chess_path
    assert_select ".eg-right a[href=?]", games_quiz_path
    # Phones reach the left column's shortcuts through the Discover sheet.
    [ circles_path, answered_prayers_path, bookmarks_path, people_path, search_path, games_path, church_history_path, blog_path ].each do |path|
      assert_select ".eg-right .eg-quicklinks a[href=?]", path
    end
  end

  test "feed chrome uses icons, not emoji" do
    get feed_path
    [ ".eg-left", ".eg-right", ".eg-today", ".eg-composer", ".eg-tabs", "nav.eg-topbar", "nav.eg-bottom" ].each do |sel|
      css_select(sel).each { |el| assert_no_match EMOJI, el.text, "#{sel} still shows an emoji" }
    end
  end

  test "tabs are all there and swap the feed frame" do
    get feed_path
    assert_select "turbo-frame#feed_stream .eg-tabs .fc-tab[data-turbo-frame='feed_stream']", 5
    assert_select ".eg-tabs .fc-tab.is-active", "Recent"
  end

  test "a prayer request gets the gold band and the big I'm praying button" do
    @post.update!(prayer_status: :prayer_pending)
    get feed_path
    card = "##{ActionView::RecordIdentifier.dom_id(@post)}"
    assert_select "#{card}.is-prayer .eg-post-band", /Prayer request/
    assert_select "#{card} form[action=?] button.eg-pray-big", join_prayer_chain_post_path(@post), text: /I'm praying/
  end

  test "pinned breaths are labelled, not emoji-marked" do
    @post.update!(featured: true)
    get feed_path
    assert_select ".fc-pinned-label svg"
    assert_no_match(/📌/, response.body)
    assert_select ".fc-pinned-card .eg-post.is-pinned .eg-post-flag.is-pinned", /Pinned/
  end

  test "the top bar has the pill nav, one badge style and the app's native hooks once each" do
    get feed_path
    assert_select "nav.eg-topbar .eg-pills .eg-pill.is-active[href=?]", feed_path
    assert_select "nav.eg-topbar .eg-pills a[href=?]", resources_root_path
    assert_select "nav.eg-topbar .eg-breathe[data-action='click->composer-modal#open']"
    %w[compose bible theme sign-out].each do |action|
      assert_select "[data-native-action=?]", action, 1
    end
    assert_select ".fc-count-badge.is-mint", false
  end
end

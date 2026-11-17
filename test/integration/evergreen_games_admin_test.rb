# frozen_string_literal: true

require "test_helper"

# Evergreen redesign of the games hub, the game screens and admin: real icons
# instead of emoji, serif page titles, and only real data on the cards.
class EvergreenGamesAdminTest < ActionDispatch::IntegrationTest
  EMOJI = /[\u{1F300}-\u{1FAFF}\u{2600}-\u{26FF}\u{2700}-\u{27BF}]/

  setup do
    @player = User.create!(username: "eg_player", email: "eg_player@example.com",
                           password: "password123", password_confirmation: "password123")
  end

  test "the games hub shows icon tiles, real bests and the leaderboard pill" do
    GameAttempt.create!(user: @player, kind: :verse_memory, score: 4, max_score: 5)
    sign_in @player
    get games_path
    assert_response :success

    assert_select "h1.fc-games-title", "Games"
    assert_select "a.fc-games-lbpill[href='#leaderboard']", /resets in/
    assert_select ".fc-games-stats .fc-games-stat", 4
    assert_select "a.fc-games-feature[href=?]", games_chess_path, /Chess puzzle of the day/
    assert_select ".fc-games-card", GamesHelper::HUB_GAMES.size
    assert_select ".fc-games-card .fc-gtile svg", GamesHelper::HUB_GAMES.size
    assert_select ".fc-games-card[data-game=verse_memory] .fc-games-card-best", "Best: 4"
    assert_select ".fc-games-card[data-game=bible_quiz] .fc-games-card-best", "Not played yet"
    assert_select "#leaderboard"

    main = css_select("main.fc-games").first.to_html
    assert_no_match EMOJI, main.gsub("Four emoji", "")
  end

  test "every game screen has the shared header with an icon tile and no emoji in its chrome" do
    sign_in @player
    { games_quiz_path => "Bible Quiz", games_verse_memory_path => "Verse Memory",
      games_history_path => "Church History", games_character_match_path => "Character Match",
      games_reference_scramble_path => "Reference Scramble", games_pic_word_path => "4 Pics 1 Word" }.each do |path, title|
      get path
      assert_response :success
      assert_select "header.fc-games-head h1.fc-games-title", title
      assert_select "header.fc-games-head .fc-gtile svg"
      assert_select "a.fc-games-back[href=?]", games_path
      assert_no_match EMOJI, css_select("header.fc-games-head").first.to_html
    end
  end

  test "game icons come from the icon set, one per kind" do
    GamesHelper::GAME_KIND_META.each_value do |meta|
      assert IconHelper::ICONS.key?(meta[:icon]), "#{meta[:icon]} should be a real icon"
      assert_no_match EMOJI, meta.values.join
    end
  end

  test "admin uses sentence-case titles, the evergreen shell and no emoji icons" do
    admin = User.create!(username: "eg_admin", email: "eg_admin@example.com", password: "password123",
                         password_confirmation: "password123", role: :admin)
    sign_in admin

    get admin_root_path
    assert_response :success
    assert_select "h1.admin-page-title", "Dashboard"
    assert_select ".admin-side-link.is-active", /Dashboard/
    assert_select ".admin-side-link", text: /Golden breaths/
    assert_select ".adash-safety em svg"
    assert_no_match EMOJI, css_select(".admin-shell").first.to_html

    get admin_users_path
    assert_select "h1.admin-page-title", "Users"
    assert_select "a.admin-filter-pill.is-active[aria-current=true]"

    get admin_rooms_path
    assert_select "h1.admin-page-title", "Rooms"
  end
end

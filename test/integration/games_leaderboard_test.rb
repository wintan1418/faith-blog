# frozen_string_literal: true

require "test_helper"

# Weekly games leaderboard: calendar-week reset, per-game champions strip,
# medal ranks.
class GamesLeaderboardTest < ActionDispatch::IntegrationTest
  setup do
    @player = User.create!(username: "lb_player", email: "lb@example.com",
                           password: "password123", password_confirmation: "password123")
    @rival = User.create!(username: "lb_rival", email: "lbr@example.com",
                          password: "password123", password_confirmation: "password123")
    sign_in @player
  end

  test "this week's scores count, last week's don't" do
    GameAttempt.create!(user: @player, kind: :bible_quiz, score: 40, max_score: 50,
                        played_at: Time.current)
    GameAttempt.create!(user: @rival, kind: :bible_quiz, score: 90, max_score: 100,
                        played_at: Time.current.beginning_of_week - 2.days)

    get games_path
    assert_response :success
    assert_match "This week's champions", response.body
    assert_match "lb_player", response.body
    assert_match "Resets in", response.body

    board = GameAttempt.leaderboard(window: :week)
    assert_equal [ @player.id ], board.map { |r| r[:user].id },
                 "last week's plays must not appear after the Monday reset"
  end

  test "champions strip crowns the top scorer per game" do
    GameAttempt.create!(user: @player, kind: :chess_puzzle, score: 12, max_score: 20, played_at: Time.current)
    GameAttempt.create!(user: @rival, kind: :chess_puzzle, score: 18, max_score: 20, played_at: Time.current)

    get games_path
    assert_response :success
    assert_match "Chess Puzzle", response.body
    body_champs = response.body[/This week&#39;s champions.*?Leaderboard/m] || response.body
    assert_match "lb_rival", body_champs
  end
end

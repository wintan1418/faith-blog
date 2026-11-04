# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# The chess puzzle page: its heading can be updated for each new puzzle.
class ChessPuzzlePageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  PUZZLE = { id: "abc12", rating: 1838, plays: 10, themes: %w[middlegame fork], solution: %w[e2e4 e7e5 g1f3],
             fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", last_move: nil,
             link: "https://lichess.org/training/abc12", side_to_move: "white" }.freeze

  test "the heading parts are targets the board updates for a practice puzzle" do
    pass = SecureRandom.base58(16)
    sign_in User.create!(username: "chess_qa", email: "chess-qa@example.com", password: pass, password_confirmation: pass)

    Lichess::DailyPuzzle.stub(:fetch, PUZZLE) { get games_chess_path }

    assert_response :success
    assert_select "[data-chess-puzzle-target=kicker]", text: /White to move/
    assert_select "[data-chess-puzzle-target=rating]", text: "Rating 1838"
    assert_select "[data-chess-puzzle-target=themes]"
    assert_select "[data-chess-puzzle-target=tier]"
  end
end

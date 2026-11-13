# frozen_string_literal: true

require "application_system_test_case"
require "minitest/mock"

# Tester: "I got a checkmate but because it wasn't the move, it wasn't
# counted." A mating puzzle can often be mated another way than the line
# Lichess lists. The board only accepted a different move when that move was
# mate itself, so in a mate-in-2 another first move that forces mate was
# treated as wrong. Now any move that still forces mate in time is accepted,
# the board defends, and mating it solves the puzzle.
class ChessOtherMatesTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  driven_by :selenium, using: :headless_chrome, screen_size: [ 412, 900 ]

  # Two rooks against a lone king on g8: White mates in 2. Lichess lists
  # Rb7 then Ra8#; Ra7 then Rb8# mates just as surely.
  PUZZLE = { id: "mate2", rating: 900, plays: 10, themes: %w[mateIn2 endgame], solution: %w[b5b7 g8f8 a6a8],
             fen: "6k1/8/R7/1R6/8/8/8/6K1 w - - 0 1", last_move: nil,
             link: "https://lichess.org/training/mate2", side_to_move: "white" }.freeze

  setup do
    @member = create_member("chess_mater", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i,
                                           tour_completed_at: Time.current, onboarding_dismissed_at: Time.current)
    login_as @member, scope: :user
  end

  teardown { Warden.test_reset! }

  def play(from, to)
    find(".fc-chess-sq[data-square='#{from}']").click
    find(".fc-chess-sq[data-square='#{to}']").click
  end

  test "a different first move that forces mate is accepted and the mate counts" do
    Lichess::DailyPuzzle.stub(:fetch, PUZZLE) do
      visit games_chess_path
      assert_selector ".fc-chess-sq[data-square='a6'] .fc-chess-piece"

      play("a6", "a7") # not the listed Rb7, but it forces mate too
      assert_selector "[data-chess-puzzle-target=status]", text: "That works too"
      assert_selector "[data-chess-puzzle-target=status]", text: "Your move." # the board answered

      king = page.evaluate_script(%(document.querySelector(".fc-chess-piece.is-b").closest("[data-square]").dataset.square))
      assert_includes %w[f8 h8], king
      play("b5", "b8") # mate on the back rank
      assert_selector "[data-chess-puzzle-target=status]", text: "Puzzle solved"
      assert_selector "[data-chess-puzzle-target=tries]", text: "❤️❤️❤️"
    end
  end

  test "a move that doesn't force mate still costs a try" do
    Lichess::DailyPuzzle.stub(:fetch, PUZZLE) do
      visit games_chess_path
      assert_selector ".fc-chess-sq[data-square='a6'] .fc-chess-piece"

      play("a6", "a1")
      assert_selector "[data-chess-puzzle-target=status]", text: "Not the best move here. 2 tries left."
    end
  end
end

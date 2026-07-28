# frozen_string_literal: true

module GamesHelper
  GAME_KIND_META = {
    "bible_quiz"         => { emoji: "📖", name: "Bible Quiz" },
    "verse_memory"       => { emoji: "🧠", name: "Verse Memory" },
    "character_match"    => { emoji: "🎭", name: "Character Match" },
    "reference_scramble" => { emoji: "🔀", name: "Reference Scramble" },
    "chess_puzzle"       => { emoji: "♞", name: "Chess Puzzle" },
    "church_history"     => { emoji: "⛪", name: "Church History" },
    "pic_word"           => { emoji: "🖼️", name: "4 Pics 1 Word" }
  }.freeze

  def game_kind_meta(kind)
    GAME_KIND_META[kind.to_s] || { emoji: "🎯", name: kind.to_s.humanize }
  end

  # "Resets in 2d 14h" — the countdown that gives the weekly board a pulse.
  def leaderboard_reset_countdown
    remaining = (Time.current.next_week.beginning_of_week - Time.current).to_i
    days  = remaining / 86_400
    hours = (remaining % 86_400) / 3_600
    days.positive? ? "#{days}d #{hours}h" : "#{hours}h"
  end
end

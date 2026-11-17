# frozen_string_literal: true

module GamesHelper
  # Each game's icon (IconHelper name) and tint (a --game-tint-* pair defined
  # in evergreen_games.css, light and dark).
  GAME_KIND_META = {
    "bible_quiz"         => { icon: "quiz",       tint: "quiz",      name: "Bible Quiz" },
    "verse_memory"       => { icon: "quote",      tint: "verse",     name: "Verse Memory" },
    "character_match"    => { icon: "usersearch", tint: "character", name: "Character Match" },
    "reference_scramble" => { icon: "shuffle",    tint: "scramble",  name: "Reference Scramble" },
    "chess_puzzle"       => { icon: "chess",      tint: "chess",     name: "Chess Puzzle" },
    "church_history"     => { icon: "church",     tint: "history",   name: "Church History" },
    "pic_word"           => { icon: "grid",       tint: "picword",   name: "4 Pics 1 Word" }
  }.freeze

  # The "All games" grid on the hub, in display order. The chess puzzle is the
  # featured "Today's challenge" card above it, so it isn't repeated here.
  HUB_GAMES = [
    { kind: "bible_quiz", path: :games_quiz_path, meta: "5, 10 or 20 questions · Leaderboard",
      body: "Multiple choice on books, characters and verses." },
    { kind: "verse_memory", path: :games_verse_memory_path, meta: "5 blanks · Leaderboard",
      body: "Five well-known verses, one missing word each. Pick the right one." },
    { kind: "church_history", path: :games_history_path, meta: "5 questions · Leaderboard",
      body: "Fathers, reformers and missionaries who shaped the church." },
    { kind: "character_match", path: :games_character_match_path, meta: "5 figures · 4 options",
      body: "Read a short bio of a biblical figure and name them." },
    { kind: "reference_scramble", path: :games_reference_scramble_path, meta: "Fast rounds",
      body: "Read a famous verse and pick its chapter and verse." },
    { kind: "pic_word", path: :games_pic_word_path, meta: "Picture puzzle",
      body: "Four emoji, one Bible story. Guess what links them." }
  ].freeze

  def game_kind_meta(kind)
    GAME_KIND_META[kind.to_s] || { icon: "games", tint: "quiz", name: kind.to_s.humanize }
  end

  # A 52px rounded tile with the game's icon in its own tint.
  def game_icon_tile(kind, size: :md)
    meta = game_kind_meta(kind)
    content_tag(:span, render_icon(meta[:icon], classes: "fc-gtile-icon"),
                class: "fc-gtile is-#{meta[:tint]}#{' is-sm' if size == :sm}", "aria-hidden": "true")
  end

  # The page header every game screen shares: back link, icon tile, serif title, intro.
  def game_header(kind, title:, intro:, back: :games)
    back_path, back_label = back == :feed ? [ feed_path, "Feed" ] : [ games_path, "Games" ]
    content_tag(:header, class: "fc-games-head") do
      safe_join([
        link_to(back_path, class: "fc-games-back") { safe_join([ render_icon("chevronleft", classes: "h-[18px] w-[18px]"), back_label ]) },
        content_tag(:div, class: "fc-games-titlerow") do
          safe_join([ game_icon_tile(kind), content_tag(:h1, title, class: "fc-games-title") ])
        end,
        content_tag(:p, intro, class: "fc-games-intro")
      ])
    end
  end

  # "Resets in 2d 14h" — the countdown that gives the weekly board a pulse.
  def leaderboard_reset_countdown
    remaining = (Time.current.next_week.beginning_of_week - Time.current).to_i
    days  = remaining / 86_400
    hours = (remaining % 86_400) / 3_600
    days.positive? ? "#{days}d #{hours}h" : "#{hours}h"
  end
end

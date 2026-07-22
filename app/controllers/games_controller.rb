# frozen_string_literal: true

class GamesController < ApplicationController
  before_action :authenticate_user!

  def index
    @window = params[:window].to_s.presence || "week"
    @leaderboard = GameAttempt.leaderboard(window: @window.to_sym, limit: 20)
    @my_rank = GameAttempt.user_rank(current_user, window: @window.to_sym)
    @my_stats = my_stats
    @recent_attempts = current_user.game_attempts.recent.limit(5)
  end

  # GET /games/quiz — render the play page (mode-select happens client side)
  def quiz
    @themes       = Ai::Bible::QuizGenerator::THEMES
    @difficulties = Ai::Bible::QuizGenerator::DIFFICULTIES
  end

  QUIZ_LENGTHS = [ 5, 10, 20 ].freeze
  MAX_QUIZ_LENGTH = 20

  # POST /games/quiz/generate — JSON: returns N questions filtered by
  # theme + difficulty, preferring questions THIS user hasn't seen lately.
  # Falls back to on-demand AI generation if the filtered pool is too thin.
  def quiz_generate
    theme       = params[:theme].to_s.presence
    theme       = nil unless theme.nil? || Ai::Bible::QuizGenerator::THEMES.key?(theme)
    difficulty  = params[:difficulty].to_s.presence
    difficulty  = nil unless difficulty.nil? || Ai::Bible::QuizGenerator::DIFFICULTIES.include?(difficulty)
    length      = params[:length].to_i
    length      = 5 unless QUIZ_LENGTHS.include?(length)

    rows = BibleQuizQuestion.sample_for(user: current_user, theme: theme, difficulty: difficulty, count: length)

    # If the filtered pool is empty (e.g. no questions yet for this theme),
    # generate one batch on demand so the user isn't stuck.
    if rows.size < length
      begin
        generated = Ai::Bible::QuizGenerator.call(theme: theme, difficulty: difficulty)
        BibleQuizQuestion.import_from_generator!(generated)
        rows = BibleQuizQuestion.sample_for(user: current_user, theme: theme, difficulty: difficulty, count: length)
      rescue Ai::Bible::QuizGenerator::ParseError, Ai::Moderation::Client::Error => e
        Rails.logger.warn("[QuizGenerator] #{e.class}: #{e.message}")
      end
    end

    BibleQuizQuestion.mark_seen!(user: current_user, question_ids: rows.map(&:id))

    questions = rows.map do |r|
      {
        id: r.id,
        kind: r.kind,
        prompt: r.prompt,
        choices: r.choices,
        correct_index: r.correct_index,
        reference: r.reference,
        explanation: r.explanation,
        theme: r.theme,
        difficulty: r.difficulty
      }
    end
    render json: { ok: true, questions: questions, theme: theme, difficulty: difficulty }
  end

  # POST /games/quiz/flag — a player says this question's answer is wrong.
  # Two flags retire the question from the pool.
  def quiz_flag
    question = BibleQuizQuestion.find_by(id: params[:question_id])
    return render(json: { ok: false }, status: :not_found) unless question

    BibleQuizQuestion.increment_counter(:flags_count, question.id)
    render json: { ok: true }
  end

  # POST /games/quiz/submit — record the result
  def quiz_submit
    record_attempt(kind: :bible_quiz, max_cap: 50)
  end

  # GET /games/chess — Lichess daily puzzle
  def chess
    @puzzle = Lichess::DailyPuzzle.fetch
    @already_solved_today = current_user.game_attempts
                                        .game_chess_puzzle
                                        .where("played_at >= ?", Time.current.beginning_of_day)
                                        .exists?
  end

  # POST /games/chess/solved — record that the user solved today's puzzle
  def chess_solved
    puzzle = Lichess::DailyPuzzle.fetch
    return render(json: { ok: false, error: "No puzzle right now." }, status: :bad_gateway) unless puzzle

    if current_user.game_attempts.game_chess_puzzle.where("played_at >= ?", Time.current.beginning_of_day).exists?
      return render json: { ok: false, error: "Already recorded today." }, status: :unprocessable_entity
    end

    score = score_for_chess_rating(puzzle[:rating])
    attempt = current_user.game_attempts.create!(
      kind: :chess_puzzle,
      score: score,
      max_score: 5,
      details: { puzzle_id: puzzle[:id], rating: puzzle[:rating], themes: puzzle[:themes] }
    )
    render json: { ok: true, score: score, attempt_id: attempt.id }
  end

  # ──────── Character Match ────────
  def character_match; end
  # One AI call returns 5 fresh figure questions, easy → hard. The old
  # play_filtered_round(kind: "character") path was broken: QuizGenerator
  # never emits a "character" kind, so the pool stayed empty and rounds
  # repeated the same stale question after several wasted AI calls.
  def character_match_generate
    questions = Ai::Bible::CharacterMatchRound.call
    render json: {
      ok: true,
      questions: questions.map { |q| { kind: q.kind, prompt: q.prompt, choices: q.choices,
                                       correct_index: q.correct_index, difficulty: q.difficulty,
                                       reference: q.reference, explanation: q.explanation } }
    }
  rescue Ai::Bible::CharacterMatchRound::ParseError, Ai::Moderation::Client::Error => e
    Rails.logger.warn("[CharacterMatchRound] #{e.class}: #{e.message}")
    render json: { ok: false, error: "Couldn't fetch a fresh round. Try again in a moment." }, status: :bad_gateway
  end
  def character_match_submit
    record_attempt(kind: :character_match, max_cap: 50)
  end

  # ──────── Reference Scramble ────────
  def reference_scramble; end
  def reference_scramble_generate
    play_filtered_round(kind: "reference")
  end
  def reference_scramble_submit
    record_attempt(kind: :reference_scramble, max_cap: 50)
  end

  # ──────── Verse Memory ────────
  def verse_memory; end
  def verse_memory_generate
    rows = Ai::Bible::VerseMemoryRound.call
    render json: { ok: true, questions: rows }
  rescue Ai::Bible::VerseMemoryRound::Error => e
    Rails.logger.warn("[VerseMemoryRound] #{e.class}: #{e.message}")
    render json: { ok: false, error: "Couldn't fetch a verse right now." }, status: :bad_gateway
  end
  def verse_memory_submit
    record_attempt(kind: :verse_memory, max_cap: 20)
  end

  # ──────── 4 Pics 1 Word ────────
  def pic_word; end
  def pic_word_generate
    rows = Ai::Bible::PicWordRound.call
    render json: { ok: true, questions: rows }
  rescue Ai::Bible::PicWordRound::Error => e
    Rails.logger.warn("[PicWordRound] #{e.class}: #{e.message}")
    render json: { ok: false, error: "Couldn't fetch puzzles right now." }, status: :bad_gateway
  end
  def pic_word_submit
    record_attempt(kind: :pic_word, max_cap: 20)
  end

  # GET /games/history — Church History trivia play page
  def history
  end

  # POST /games/history/generate — 5 AI-generated church history questions
  def history_generate
    questions = Ai::Christian::HistoryQuiz.call
    render json: {
      ok: true,
      questions: questions.map { |q| { kind: q.kind, prompt: q.prompt, choices: q.choices,
                                       correct_index: q.correct_index, reference: q.reference,
                                       explanation: q.explanation } }
    }
  rescue Ai::Christian::HistoryQuiz::ParseError, Ai::Moderation::Client::Error => e
    Rails.logger.warn("[HistoryQuiz] #{e.class}: #{e.message}")
    render json: { ok: false, error: "Couldn't fetch a fresh quiz. Try again in a moment." }, status: :bad_gateway
  end

  # POST /games/history/submit
  def history_submit
    record_attempt(kind: :church_history, max_cap: 50)
  end

  private

  # Generate a round filtered by a SINGLE question kind (used by Character
  # Match + Reference Scramble — same gamy quiz UI, different filter).
  def play_filtered_round(kind:)
    length = params[:length].to_i
    length = 5 unless QUIZ_LENGTHS.include?(length)
    difficulty = params[:difficulty].to_s.presence
    difficulty = nil unless difficulty.nil? || Ai::Bible::QuizGenerator::DIFFICULTIES.include?(difficulty)

    rows = BibleQuizQuestion.sample_for(user: current_user, kind: kind, difficulty: difficulty, count: length)

    # Pool too thin? Generate on demand.
    if rows.size < length
      attempts = 0
      while rows.size < length && attempts < 3
        begin
          generated = Ai::Bible::QuizGenerator.call(difficulty: difficulty)
          # Keep only matching kind from the AI batch.
          BibleQuizQuestion.import_from_generator!(generated.select { |q| q.kind == kind })
        rescue Ai::Bible::QuizGenerator::ParseError, Ai::Moderation::Client::Error => e
          Rails.logger.warn("[FilteredQuiz #{kind}] #{e.class}: #{e.message}")
        end
        attempts += 1
        rows = BibleQuizQuestion.sample_for(user: current_user, kind: kind, difficulty: difficulty, count: length)
      end
    end

    BibleQuizQuestion.mark_seen!(user: current_user, question_ids: rows.map(&:id))

    questions = rows.map do |r|
      { id: r.id, kind: r.kind, prompt: r.prompt, choices: r.choices, correct_index: r.correct_index,
        reference: r.reference, explanation: r.explanation, theme: r.theme, difficulty: r.difficulty }
    end
    render json: { ok: true, questions: questions, difficulty: difficulty }
  end

  def record_attempt(kind:, max_cap:)
    score     = params[:score].to_i
    max_score = params[:max_score].to_i.clamp(1, max_cap)
    duration  = params[:duration_ms].to_i
    details   = sanitized_game_details

    attempt = current_user.game_attempts.create!(
      kind: kind,
      score: score.clamp(0, max_score),
      max_score: max_score,
      duration_ms: duration,
      details: details
    )

    render json: {
      ok: true,
      attempt_id: attempt.id,
      rank: GameAttempt.user_rank(current_user, window: :week)
    }
  end

  # `details` is free-form per-game stats stored as jsonb. We don't trust the
  # client, so instead of permit! (which let arbitrary nested structures in)
  # we keep at most 50 keys mapped to scalar values, dropping nested
  # hashes/arrays and truncating long strings.
  def sanitized_game_details
    raw = params[:details]
    return {} unless raw.is_a?(ActionController::Parameters)

    raw.to_unsafe_h.first(50).each_with_object({}) do |(key, value), acc|
      acc[key.to_s] = case value
      when String then value.first(1000)
      when Numeric, true, false, nil then value
      else value.to_s.first(1000)
      end
    end
  end

  def score_for_chess_rating(rating)
    case rating
    when 0..1499    then 1
    when 1500..1999 then 2
    when 2000..2499 then 3
    else 5
    end
  end

  def my_stats
    week = current_user.game_attempts.this_week
    {
      plays_this_week:   week.count,
      score_this_week:   week.sum(:score),
      best_ever:         current_user.game_attempts.maximum(:score) || 0,
      lifetime_plays:    current_user.game_attempts.count
    }
  end
end

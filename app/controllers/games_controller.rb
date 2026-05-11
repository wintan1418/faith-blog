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

  # GET /games/quiz — render the play page (questions generated client-side on click)
  def quiz
  end

  # POST /games/quiz/generate — JSON: returns 5 questions shuffled from the
  # BibleQuizQuestion pool. Falls back to on-demand AI generation only if
  # the pool is empty (first install, before the seed task runs).
  def quiz_generate
    rows = BibleQuizQuestion.sample(5)
    if rows.size < 5
      generated = Ai::Bible::QuizGenerator.call
      BibleQuizQuestion.import_from_generator!(generated)
      rows = BibleQuizQuestion.sample(5)
    end

    questions = rows.map do |r|
      {
        kind: r.kind,
        prompt: r.prompt,
        choices: r.choices,
        correct_index: r.correct_index,
        reference: r.reference,
        explanation: r.explanation
      }
    end
    render json: { ok: true, questions: questions }
  rescue Ai::Bible::QuizGenerator::ParseError, Ai::Moderation::Client::Error => e
    Rails.logger.warn("[QuizGenerator] #{e.class}: #{e.message}")
    render json: { ok: false, error: "Couldn't fetch a fresh quiz. Try again in a moment." }, status: :bad_gateway
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

  # GET /games/trivia
  def trivia
  end

  # POST /games/trivia/generate — pull 5 religion questions from Open Trivia DB
  def trivia_generate
    questions = Trivia::Religion.fetch_batch(5)
    render json: { ok: true, questions: questions }
  rescue Trivia::Religion::Error => e
    Rails.logger.warn("[Trivia::Religion] #{e.class}: #{e.message}")
    render json: { ok: false, error: "Couldn't fetch trivia right now. Try again in a moment." }, status: :bad_gateway
  end

  # POST /games/trivia/submit
  def trivia_submit
    record_attempt(kind: :religion_trivia, max_cap: 50)
  end

  private

  def record_attempt(kind:, max_cap:)
    score     = params[:score].to_i
    max_score = params[:max_score].to_i.clamp(1, max_cap)
    duration  = params[:duration_ms].to_i
    details   = params[:details].is_a?(ActionController::Parameters) ? params[:details].permit!.to_h : {}

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

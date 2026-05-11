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

  # POST /games/quiz/generate — JSON: returns the 5 questions for this play
  def quiz_generate
    questions = Ai::Bible::QuizGenerator.call
    render json: {
      ok: true,
      questions: questions.map { |q| { kind: q.kind, prompt: q.prompt, choices: q.choices,
                                       correct_index: q.correct_index, reference: q.reference,
                                       explanation: q.explanation } }
    }
  rescue Ai::Bible::QuizGenerator::ParseError, Ai::Moderation::Client::Error => e
    Rails.logger.warn("[QuizGenerator] #{e.class}: #{e.message}")
    render json: { ok: false, error: "Couldn't fetch a fresh quiz. Try again in a moment." }, status: :bad_gateway
  end

  # POST /games/quiz/submit — record the result
  def quiz_submit
    score     = params[:score].to_i
    max_score = params[:max_score].to_i.clamp(1, 50)
    duration  = params[:duration_ms].to_i
    details   = params[:details].is_a?(ActionController::Parameters) ? params[:details].permit!.to_h : {}

    attempt = current_user.game_attempts.create!(
      kind: :bible_quiz,
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

  private

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

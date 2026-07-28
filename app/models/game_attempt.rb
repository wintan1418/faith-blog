# frozen_string_literal: true

class GameAttempt < ApplicationRecord
  belongs_to :user
  after_create_commit -> { BadgeCheckJob.perform_later(user_id) }, if: -> { user_id.present? }

  enum :kind, {
    bible_quiz: 0,
    verse_memory: 1,
    character_match: 2,
    reference_scramble: 3,
    chess_puzzle: 4,
    church_history: 5,
    pic_word: 6
  }, prefix: :game

  validates :score, :max_score, presence: true, numericality: { greater_than_or_equal_to: 0 }

  before_validation :default_played_at, on: :create

  scope :recent,      -> { order(played_at: :desc) }
  # Calendar windows so the board truly RESETS — Monday 00:00 and the 1st —
  # instead of a rolling tail where old scores fade out gradually.
  scope :this_week,   -> { where("played_at >= ?", Time.current.beginning_of_week) }
  scope :this_month,  -> { where("played_at >= ?", Time.current.beginning_of_month) }

  # Aggregate leaderboard. Returns rows of {user, total_score, plays, best}.
  # window: :week | :month | :all
  def self.leaderboard(window: :week, limit: 20, kind: nil)
    scope = self
    scope = scope.where(kind: kind) if kind
    scope = case window
            when :week  then scope.this_week
            when :month then scope.this_month
            else scope
            end

    rows = scope
      .group(:user_id)
      .select("user_id, SUM(score) AS total_score, COUNT(*) AS plays, MAX(score) AS best")
      .order(Arel.sql("total_score DESC, best DESC, plays DESC"))
      .limit(limit)

    users = User.where(id: rows.map(&:user_id)).includes(:profile).index_by(&:id)
    rows.map do |row|
      {
        user:        users[row.user_id],
        total_score: row.total_score.to_i,
        plays:       row.plays.to_i,
        best:        row.best.to_i
      }
    end.reject { |r| r[:user].nil? }
  end

  def self.user_rank(user, window: :week, kind: nil)
    board = leaderboard(window: window, limit: 500, kind: kind)
    idx = board.find_index { |r| r[:user]&.id == user.id }
    idx ? idx + 1 : nil
  end

  private

  def default_played_at
    self.played_at ||= Time.current
  end
end

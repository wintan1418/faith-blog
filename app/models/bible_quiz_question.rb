# frozen_string_literal: true

class BibleQuizQuestion < ApplicationRecord
  has_many :user_seen_quiz_questions, dependent: :delete_all

  validates :prompt, :correct_index, :fingerprint, presence: true
  validates :fingerprint, uniqueness: true
  validate  :choices_well_formed

  before_validation :set_fingerprint, on: :create

  scope :recent, -> { order(created_at: :desc) }
  scope :by_theme,      ->(theme)      { theme.present?      ? where(theme: theme)           : all }
  scope :by_difficulty, ->(difficulty) { difficulty.present? ? where(difficulty: difficulty) : all }
  scope :by_kind,       ->(kind)       { kind.present?       ? where(kind: kind)             : all }

  # Pull N random questions — preferring questions THIS USER hasn't seen in
  # the last 30 days. Falls back to least-recently-seen when the unseen
  # pool is exhausted so the round is never short. theme/difficulty/kind
  # are optional filters; pass nil/"" to sample across all.
  # Questions two players have flagged as wrong stop being served.
  scope :trusted, -> { where("flags_count < 2") }

  def self.sample_for(user:, theme: nil, difficulty: nil, kind: nil, count: 5)
    candidates = trusted.by_theme(theme).by_difficulty(difficulty).by_kind(kind)
    return [] if candidates.none?

    seen_ids = UserSeenQuizQuestion
                .where(user_id: user.id)
                .where("last_seen_at >= ?", 30.days.ago)
                .pluck(:bible_quiz_question_id)

    fresh = candidates.where.not(id: seen_ids).order(Arel.sql("RANDOM()")).limit(count).to_a
    return fresh if fresh.size >= count

    # Top up with oldest-seen questions when the unseen pool runs dry.
    need = count - fresh.size
    fill_ids = UserSeenQuizQuestion
                .where(user_id: user.id)
                .where(bible_quiz_question_id: candidates.select(:id))
                .order(last_seen_at: :asc)
                .limit(need * 3)
                .pluck(:bible_quiz_question_id)
    filler = candidates.where(id: fill_ids).order(Arel.sql("RANDOM()")).limit(need).to_a

    fresh + filler
  end

  # Legacy entrypoint kept for any callers that don't have a user context.
  def self.sample(n = 5)
    order(Arel.sql("RANDOM()")).limit(n).to_a
  end

  # Record that the given user saw these questions right now.
  # Note: do NOT include :updated_at in update_only — Rails auto-appends
  # it on upsert and PG rejects 'SET updated_at = …, updated_at = …'.
  def self.mark_seen!(user:, question_ids:)
    return if question_ids.blank?

    now = Time.current
    rows = question_ids.uniq.map do |qid|
      { user_id: user.id, bible_quiz_question_id: qid, last_seen_at: now, created_at: now, updated_at: now }
    end
    UserSeenQuizQuestion.upsert_all(rows, unique_by: :idx_seen_user_q,
                                          update_only: [ :last_seen_at ])
  end

  def self.import_from_generator!(questions)
    inserted = 0
    questions.each do |q|
      row = create(
        kind: q.kind.to_s,
        prompt: q.prompt,
        choices: q.choices,
        correct_index: q.correct_index,
        reference: q.reference,
        explanation: q.explanation,
        difficulty: q.respond_to?(:difficulty) ? q.difficulty.to_s : "medium",
        theme: q.respond_to?(:theme) ? q.theme.to_s : nil
      )
      inserted += 1 if row.persisted?
    end
    inserted
  end

  private

  def set_fingerprint
    self.fingerprint ||= Digest::SHA1.hexdigest(prompt.to_s.downcase.strip)
  end

  def choices_well_formed
    return errors.add(:choices, "must have exactly 4 entries") unless choices.is_a?(Array) && choices.size == 4
    return errors.add(:correct_index, "out of range") unless correct_index.to_i.between?(0, 3)
  end
end

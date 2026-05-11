# frozen_string_literal: true

class BibleQuizQuestion < ApplicationRecord
  validates :prompt, :correct_index, :fingerprint, presence: true
  validates :fingerprint, uniqueness: true
  validate  :choices_well_formed

  before_validation :set_fingerprint, on: :create

  scope :recent, -> { order(created_at: :desc) }

  # Pull N random questions, weighted toward variety.
  def self.sample(n = 5)
    order(Arel.sql("RANDOM()")).limit(n).to_a
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
        difficulty: q.respond_to?(:difficulty) ? q.difficulty.to_s : "medium"
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

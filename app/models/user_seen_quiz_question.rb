# frozen_string_literal: true

class UserSeenQuizQuestion < ApplicationRecord
  belongs_to :user
  belongs_to :bible_quiz_question

  validates :user_id, uniqueness: { scope: :bible_quiz_question_id }

  scope :recent, -> { where("last_seen_at >= ?", 30.days.ago) }
end

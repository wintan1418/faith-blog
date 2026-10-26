# frozen_string_literal: true

# A school on someone's professional profile.
class Education < ApplicationRecord
  belongs_to :user

  validates :school, presence: true, length: { maximum: 120 }
  validates :qualification, :field_of_study, length: { maximum: 100 }
  validates :start_year, :end_year, numericality: { only_integer: true, greater_than: 1900, less_than: 2100 }, allow_nil: true
  validates :description, length: { maximum: 1000 }
  validate :ends_after_start

  scope :ordered, -> { order(Arel.sql("COALESCE(end_year, 9999) DESC, start_year DESC NULLS LAST")) }

  def years
    [ start_year, end_year ].compact.uniq.join(" – ").presence
  end

  private

  def ends_after_start
    errors.add(:end_year, "must be after the start") if start_year && end_year && end_year < start_year
  end
end

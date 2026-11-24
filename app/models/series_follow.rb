# frozen_string_literal: true

# A reader following a series: they get an alert (and a push) when the writer
# adds a new part. The writer can't follow their own series.
class SeriesFollow < ApplicationRecord
  belongs_to :user
  belongs_to :series

  validates :series_id, uniqueness: { scope: :user_id }
  validate :not_the_author

  private

  def not_the_author
    errors.add(:base, "You can't follow your own series") if series && series.user_id == user_id
  end
end

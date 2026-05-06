# frozen_string_literal: true

class GoldenBreath < ApplicationRecord
  validates :text, presence: true, length: { minimum: 4, maximum: 1200 }
  validates :author_name, length: { maximum: 120 }, allow_blank: true
  validates :reference,   length: { maximum: 120 }, allow_blank: true
  validates :source_url,  length: { maximum: 500 }, allow_blank: true

  scope :active,  -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, created_at: :desc) }

  # Stable golden-breath-of-the-day rotation, one a day.
  def self.of_the_day
    pool = active.ordered.to_a
    return nil if pool.empty?

    pool[Date.current.yday % pool.size]
  end

  def author_initial
    author_name.to_s.strip.first&.upcase || "G"
  end
end

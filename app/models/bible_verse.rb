# frozen_string_literal: true

class BibleVerse < ApplicationRecord
  validates :text, presence: true, length: { minimum: 4, maximum: 800 }
  validates :reference, length: { maximum: 120 }, allow_blank: true

  scope :active,  -> { where(active: true) }
  scope :ordered, -> { order(position: :asc, created_at: :desc) }

  # Stable "verse of the day" — same verse for everyone on a given day,
  # rotates by day-of-year, pulls only from active rows.
  def self.of_the_day
    pool = active.ordered.to_a
    return nil if pool.empty?

    pool[Date.current.yday % pool.size]
  end
end

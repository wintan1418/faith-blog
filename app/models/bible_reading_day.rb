# frozen_string_literal: true

# A day a member read Scripture, in their own time zone (one row per member
# per local date). Streaks, the once-a-day seeds and the "N brethren read
# today" count all come from these rows.
class BibleReadingDay < ApplicationRecord
  SOURCES = %w[card chapter dwell].freeze

  belongs_to :user

  validates :read_on, presence: true, uniqueness: { scope: :user_id }
  validates :source, inclusion: { in: SOURCES }

  # How many members read on `date`. Cached for a few minutes, and computed
  # straight from the table whenever the cache store is unavailable.
  def self.readers_on(date)
    Rails.cache.fetch([ "bible-readers", date.iso8601 ], expires_in: 5.minutes) { where(read_on: date).count }
  rescue StandardError => e
    Rails.logger.warn("[daily_bible] cache unavailable (#{e.class}: #{e.message}); counting directly")
    where(read_on: date).count
  end
end

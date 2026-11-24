# frozen_string_literal: true

# The last answer Google Search Console gave for one report ("queries_28d",
# "sitemaps", "inspection:<url>", ...). Kept in the database so the admin page
# never waits on Google and survives cache trouble.
class SearchConsoleReport < ApplicationRecord
  validates :kind, presence: true

  def self.for(kind)
    find_by(kind: kind)
  end

  def self.data_for(kind)
    self.for(kind)&.data
  end

  def self.store!(kind, data: nil, error: nil)
    record = find_or_initialize_by(kind: kind)
    record.data = data unless data.nil?
    record.error = error
    record.fetched_at = Time.current if error.nil?
    record.save!
    record
  rescue ActiveRecord::RecordNotUnique
    retry
  end
end

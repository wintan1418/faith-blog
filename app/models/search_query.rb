# frozen_string_literal: true

# One full search (not the instant dropdown's keystrokes), for the admin's
# top and zero-result searches. Stores the normalized words, the tab, the
# result count and the member's id; never an IP. from: names, email
# addresses and long digit runs (phone numbers) are blanked out first.
class SearchQuery < ApplicationRecord
  belongs_to :user, optional: true

  scope :since, ->(time) { where(created_at: time..) }
  scope :zero_results, -> { where(results_count: 0) }

  def self.normalize(text)
    SiteSearch::Query.normalize(text).downcase
                     .gsub(/(^|\s)from:\S+/, '\1from:…')
                     .gsub(/\S+@\S+\.\S+/, "[email]")
                     .gsub(/\+?\d[\d\s\-().]{6,}\d/, "[number]")
                     .squish.first(120)
  end

  # Never lets logging break a search.
  def self.log(text:, tab:, results_count:, user: nil, filtered: false)
    query = normalize(text)
    return if query.blank?

    create!(query: query, tab: tab.to_s.first(20), results_count: results_count.to_i, user_id: user&.id, filtered: filtered)
  rescue StandardError => e
    Rails.logger.warn("[search] log failed: #{e.class}: #{e.message}")
    nil
  end

  # [[query, searches, members, zero_result_searches], ...]
  def self.top(since:, limit: 25, zero_only: false)
    scope = since(since)
    scope = scope.zero_results if zero_only
    scope.group(:query)
         .order(Arel.sql("COUNT(*) DESC"), :query)
         .limit(limit)
         .pluck(:query, Arel.sql("COUNT(*)"), Arel.sql("COUNT(DISTINCT user_id)"),
                Arel.sql("COUNT(*) FILTER (WHERE results_count = 0)"))
  end
end

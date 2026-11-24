# frozen_string_literal: true

# Admin → Site search: what members look for on Brethreign, and what finds
# nothing (content worth writing, or words search should understand).
# Built from SearchQuery: normalized words and counts, no IPs.
class Admin::SearchInsightsController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"

  PERIODS = { "7d" => 7.days, "30d" => 30.days, "90d" => 90.days }.freeze

  def show
    @period = PERIODS.key?(params[:period]) ? params[:period] : "7d"
    since = PERIODS.fetch(@period).ago
    scope = SearchQuery.since(since)
    @totals = {
      searches: scope.count,
      members: scope.where.not(user_id: nil).distinct.count(:user_id),
      zero: scope.zero_results.count,
      filtered: scope.where(filtered: true).count
    }
    @top = SearchQuery.top(since: since, limit: 30)
    @zero = SearchQuery.top(since: since, limit: 30, zero_only: true)
    @tabs = scope.group(:tab).order(Arel.sql("COUNT(*) DESC")).count
    @terms_count = SearchTerm.count
  end
end

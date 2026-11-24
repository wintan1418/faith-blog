# frozen_string_literal: true

# One search page with tabs (Top, Breaths, People, Rooms, Series, Bible,
# Resources), the header's instant dropdown (#suggest) and a member's recent
# searches.
#
# Every tab reuses SiteSearch::Visibility: search never finds anything the
# searcher couldn't reach by browsing. Filters live in the URL, so a results
# page can be shared.
class SearchController < ApplicationController
  TABS = %w[top breaths people rooms series bible resources].freeze
  DATES = SiteSearch::PostSearch::DATES
  TYPES = SiteSearch::PostSearch::TYPES
  SORTS = SiteSearch::PostSearch::SORTS
  SUGGEST_BREATHS = 4
  # Old links: /search?type=users|resources|posts.
  LEGACY_TYPES = { "users" => "people", "resources" => "resources", "posts" => "breaths" }.freeze

  member_rate_limit to: 40, within: 1.minute, only: :index, name: "search"
  member_rate_limit to: 150, within: 1.minute, only: :suggest, name: "search-suggest"
  before_action :authenticate_user!, only: :clear_recent
  # The dropdown's background requests aren't page views.
  skip_after_action :track_page_view, only: %i[suggest clear_recent]

  helper_method :search_params, :filters_active?

  def index
    @tab = TABS.include?(params[:tab]) ? params[:tab] : LEGACY_TYPES.fetch(params[:type], "top")
    @query = SiteSearch::Query.new(params[:q])
    @visibility = SiteSearch::Visibility.new(current_user)
    @filters = build_filters
    @rooms_for_filter = @visibility.rooms_scope.ordered.select(:id, :name, :slug)
    return if @query.blank?

    # "john 3 16" goes straight to the verse.
    if @tab == "top" && params[:jump] != "0" && !filters_active? && (reference = sections.reference)
      remember(results: 1)
      return redirect_to(scripture_page_path(reference.slug))
    end

    return authenticate_user! if @tab == "people" && !user_signed_in?

    results = send(:"search_#{@tab}")
    remember(results: results)
  end

  # The header dropdown: a few people, rooms and breaths for what's typed, or
  # the member's recent searches when the box is empty.
  def suggest
    @query = SiteSearch::Query.new(params[:q].to_s.first(SiteSearch::Query::MAX_LENGTH))
    @visibility = SiteSearch::Visibility.new(current_user)
    if @query.blank? || @query.text.length < 2
      @recent = RecentSearch.for(current_user).to_a
    else
      @reference = sections.reference
      @people = sections.people_quick(limit: 3)
      @rooms = sections.rooms(limit: 3).to_a
      search = SiteSearch::PostSearch.new(@query, visibility: @visibility, filters: {})
      @breaths = search.call(per_page: SUGGEST_BREATHS, snippets: false, include_replies: false).hits
    end
    render partial: "search/suggestions", formats: [ :html ], layout: false
  end

  def clear_recent
    RecentSearch.where(user_id: current_user.id).delete_all
    respond_to do |format|
      format.html { redirect_back fallback_location: search_path, notice: "Recent searches cleared.", status: :see_other }
      format.any { head :no_content }
    end
  end

  private

  def sections
    @sections ||= SiteSearch::Sections.new(@query, @visibility)
  end

  def search_top
    @breaths = post_search.call(page: 1, per_page: 6)
    @people = sections.people(limit: 3).to_a
    @rooms = sections.rooms(limit: 3).to_a
    @reference = sections.reference
    @resources = sections.resources(limit: 2).to_a
    @series = sections.series(limit: 2).to_a
    @series_parts = sections.series_part_counts(@series)
    load_fallbacks(@breaths)
    @breaths.total + @people.size + @rooms.size + @resources.size + @series.size + (@reference ? 1 : 0)
  end

  def search_breaths
    @breaths = post_search.call(page: params[:page])
    load_fallbacks(@breaths)
    @breaths.total
  end

  def search_people
    @page = params[:page].to_i.clamp(1, 50)
    @people = sections.people(limit: 21, offset: (@page - 1) * 20).to_a
    @more = @people.size > 20
    @people = @people.first(20)
    @people.size
  end

  def search_rooms
    @rooms = sections.rooms(limit: 30).to_a
    @rooms.size
  end

  def search_bible
    @reference = sections.reference
    @verses = sections.verses(limit: 20)
    @verses.size + (@reference ? 1 : 0)
  end

  def search_series
    @series = sections.series(limit: 30).to_a
    @series_parts = sections.series_part_counts(@series)
    @series.size
  end

  def search_resources
    @resources = sections.resources(limit: 30).to_a
    @resources.size
  end

  def post_search
    @post_search ||= SiteSearch::PostSearch.new(@query, visibility: @visibility, filters: @filters)
  end

  # Little or nothing found: suggest a spelling and show close title matches.
  def load_fallbacks(result)
    return if result.total >= 3

    @suggestion = SiteSearch::Suggester.new(@query).suggestion
    seen = result.hits.map { |h| h.post.id }
    close = []
    if @suggestion
      corrected = SiteSearch::PostSearch.new(@query.with_text(@suggestion), visibility: @visibility, filters: @filters)
      close += corrected.call(per_page: 6).hits
    end
    close += post_search.fuzzy_titles(limit: 6)
    @close_matches = close.uniq { |h| h.post.id }.reject { |h| seen.include?(h.post.id) }.first(6)
  end

  # Room, date range, type, from:, sort. An unknown room or member (or one
  # the viewer can't see) keeps its key with nil, which finds nothing.
  def build_filters
    filters = {}
    if params[:room].present?
      room = Room.find_by(slug: params[:room].to_s)
      filters[:room] = @visibility.room_visible?(room) ? room : nil
    end
    username = params[:from].presence&.strip&.delete_prefix("@").presence || @query.from_username
    if username
      filters[:author] = @visibility.users_scope.find_by("lower(users.username) = ?", username.to_s.downcase.first(40))
    end
    filters[:since] = DATES[params[:date]].ago if DATES.key?(params[:date])
    filters[:type] = params[:type] if TYPES.include?(params[:type])
    filters[:sort] = params[:sort] if SORTS.include?(params[:sort])
    filters
  end

  def filters_active?
    %i[room from date type].any? { |k| params[k].present? } || @query&.from_username.present?
  end

  # The URL's search state, for tabs, filters and paging links.
  def search_params(overrides = {})
    base = params.permit(:q, :tab, :room, :from, :date, :type, :sort).to_h.symbolize_keys
    base.merge(overrides).compact_blank
  end

  def remember(results:)
    SearchQuery.log(text: @query.text, tab: @tab, results_count: results, user: current_user, filtered: filters_active?)
    RecentSearch.remember(current_user, @query.text) if user_signed_in?
  end
end

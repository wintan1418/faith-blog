# frozen_string_literal: true

# The city picker's type-ahead, and "Use my location" (nearest city to a point).
class CitiesController < ApplicationController
  before_action :authenticate_user!
  skip_after_action :track_page_view, raise: false
  member_rate_limit to: 600, within: 10.minutes, only: :index, name: "city-search", json: true
  member_rate_limit to: 20, within: 10.minutes, only: :nearest, name: "city-nearest", json: true

  def index
    cities = City.search(params[:q].to_s.first(80), country: params[:country].presence || request.headers["CF-IPCountry"]).to_a
    # "· 7 breathers": only near the member's own city, only where enough live to
    # name the place, and only people they could find there anyway (so the picker
    # can't be used to survey towns far away). See BreathersAround#picker_counts.
    counts = BreathersAround.new(current_user).picker_counts(cities)
    render json: cities.map { |c| c.as_json.merge(breathers: counts[c.id].to_i) }
  end

  # The browser's position is used for this one lookup and then forgotten: it
  # comes in a POST body (not the URL, so no access log keeps it), is filtered
  # from the Rails log (filter_parameters) and is never saved.
  def nearest
    city = City.nearest(params[:lat], params[:lng])
    city ? render(json: city.as_json) : head(:not_found)
  end
end

# frozen_string_literal: true

# Admin → City changes: members who keep moving their city (Breathers around
# you), who could be hopping between towns to see who lives there, and the
# latest changes. Locations are personal data, so admins only.
class Admin::CityChangesController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"

  def index
    counts = CityChange.frequent_movers
    users = User.where(id: counts.keys).index_by(&:id)
    @movers = counts.filter_map { |user_id, n| [ users[user_id], n ] if users[user_id] }
    @pagy, @changes = pagy(CityChange.includes(:user, :from_city, :to_city).order(created_at: :desc), items: 50)
  end
end

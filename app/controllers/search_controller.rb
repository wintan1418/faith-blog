# frozen_string_literal: true

class SearchController < ApplicationController
  def index
    @query = params[:q]
    return unless @query.present?

    case params[:type]
    when "users"
      @pagy, @results = pagy(
        User
          .active
          .includes(:profile)
          .left_joins(:profile)
          .where(
            "users.username ILIKE :query OR profiles.bio ILIKE :query OR profiles.location ILIKE :query OR profiles.faith_background ILIKE :query",
            query: "%#{@query}%"
          )
          .order(:username)
      )
      @result_type = :users
    when "resources"
      @pagy, @results = pagy(Resource.approved.search(@query).includes(:resource_category, :user))
      @result_type = :resources
    else
      @pagy, @results = pagy(Post.published.search(@query).includes(:user, :room, :tags))
      @result_type = :posts
    end
  end
end

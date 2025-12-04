# frozen_string_literal: true

class SearchController < ApplicationController
  def index
    @query = params[:q]
    return unless @query.present?

    case params[:type]
    when "users"
      @pagy, @results = pagy(User.where("username ILIKE ?", "%#{@query}%").includes(:profile))
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


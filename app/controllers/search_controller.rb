# frozen_string_literal: true

class SearchController < ApplicationController
  def index
    @query = params[:q]
    return unless @query.present?

    case params[:type]
    when "users"
      # Member search is for members only — no anonymous profile probing.
      return authenticate_user! unless user_signed_in?

      @pagy, @results = pagy(User.active.includes(:profile).member_search(@query).order(:username))
      @result_type = :users
    when "resources"
      @pagy, @results = pagy(Resource.approved.search(@query).includes(:resource_category, :user))
      @result_type = :resources
    else
      @pagy, @results = pagy(Post.published.search(@query).for_cards)
      @result_type = :posts
    end
  end
end

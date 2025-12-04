# frozen_string_literal: true

class Resources::HomeController < ApplicationController
  def index
    @categories = ResourceCategory.ordered.includes(:resources)
    @featured_resources = Resource.approved.featured.includes(:resource_category, :user).limit(6)
    @recent_resources = Resource.approved.recent.includes(:resource_category, :user).limit(10)
  end
end


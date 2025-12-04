# frozen_string_literal: true

class ResourceCategoriesController < ApplicationController
  def index
    @categories = ResourceCategory.ordered.includes(:resources)
  end

  def show
    @category = ResourceCategory.friendly.find(params[:id])
    @pagy, @resources = pagy(@category.resources.approved.includes(:user).recent)
  end
end


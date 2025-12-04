# frozen_string_literal: true

class ResourceItemsController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_resource, only: [:show, :edit, :update, :destroy]

  def index
    @resources = Resource.approved.includes(:user, :resource_category).recent
    @pagy, @resources = pagy(@resources)
  end

  def show
    @resource.increment_views!
  end

  def new
    @resource = current_user.resources.build
    @categories = ResourceCategory.ordered
  end

  def create
    @resource = current_user.resources.build(resource_params)
    
    if @resource.save
      redirect_to resources_root_path, notice: "Resource submitted for approval. Thank you!"
    else
      @categories = ResourceCategory.ordered
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @categories = ResourceCategory.ordered
  end

  def update
    if @resource.update(resource_params)
      redirect_to resources_item_path(@resource), notice: "Resource updated."
    else
      @categories = ResourceCategory.ordered
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @resource.destroy
    redirect_to resources_root_path, notice: "Resource deleted."
  end

  private

  def set_resource
    @resource = Resource.friendly.find(params[:id])
  end

  def resource_params
    params.require(:resource).permit(:title, :description, :resource_type, :url, :resource_category_id, :file)
  end
end


# frozen_string_literal: true

class ResourceItemsController < ApplicationController
  before_action :authenticate_user!, except: [ :index, :show ]
  before_action :set_resource, only: [ :show, :edit, :update, :destroy ]
  before_action :authorize_resource!, only: [ :edit, :update, :destroy ]
  before_action :hide_unapproved!, only: :show

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
    @resource.assign_attributes(resource_params)
    # A member's change to an approved resource goes back to the moderators
    # (otherwise approval could be swapped for anything afterwards).
    resubmitted = @resource.approved? && !current_user.admin_or_moderator? && resource_content_changed?
    @resource.assign_attributes(approved: false, approved_by: nil, approved_at: nil) if resubmitted

    if @resource.save
      notice = resubmitted ? "Resource updated and sent back for approval." : "Resource updated."
      redirect_to resources_item_path(@resource), notice: notice
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
    params.expect(resource: [ :title, :description, :resource_type, :url, :resource_category_id, :file ])
  end

  # Until it's approved, a resource is only seen by whoever shared it and the moderators.
  def hide_unapproved!
    return if @resource.approved?
    return if user_signed_in? && (@resource.user == current_user || current_user.admin_or_moderator?)

    raise ActiveRecord::RecordNotFound
  end

  def resource_content_changed?
    @resource.changed? || @resource.attachment_changes.key?("file")
  end

  def authorize_resource!
    return if @resource.user == current_user || current_user.admin_or_moderator?

    redirect_to resources_item_path(@resource), alert: "You're not authorized to manage this resource."
  end
end

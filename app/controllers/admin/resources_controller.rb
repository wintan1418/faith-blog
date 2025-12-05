# frozen_string_literal: true

class Admin::ResourcesController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"
  before_action :set_resource, only: [:show, :edit, :update, :destroy, :approve, :reject]

  def index
    @resources = Resource.includes(:user, :resource_category).order(created_at: :desc).page(params[:page]).per(20)
  end

  def show
  end

  def new
    @resource = Resource.new
  end

  def create
    @resource = Resource.new(resource_params)
    @resource.user = current_user
    @resource.approved = true
    @resource.approved_by = current_user
    @resource.approved_at = Time.current
    
    if @resource.save
      redirect_to admin_resource_path(@resource), notice: "Resource created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @resource.update(resource_params)
      redirect_to admin_resource_path(@resource), notice: "Resource updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @resource.destroy
    redirect_to admin_resources_path, notice: "Resource deleted."
  end

  def approve
    @resource.approve!(current_user)
    ModerationLog.log_action(moderator: current_user, action: "approved_resource", target: @resource)
    
    Notification.create(
      user: @resource.user,
      actor: current_user,
      notifiable: @resource,
      notification_type: :resource_approved
    )
    
    redirect_to admin_resources_path, notice: "Resource approved."
  end

  def reject
    @resource.reject!(current_user)
    ModerationLog.log_action(moderator: current_user, action: "rejected_resource", target: @resource)
    
    Notification.create(
      user: @resource.user,
      actor: current_user,
      notifiable: @resource,
      notification_type: :resource_rejected
    )
    
    redirect_to admin_resources_path, notice: "Resource rejected."
  end

  private

  def set_resource
    @resource = Resource.find(params[:id])
  end

  def resource_params
    params.require(:resource).permit(:title, :description, :resource_type, :url, :resource_category_id, :featured)
  end
end


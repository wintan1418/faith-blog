# frozen_string_literal: true

class LikesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_likeable

  def create
    @like = current_user.likes.find_or_initialize_by(likeable: @likeable)
    @like.reaction_type = params[:reaction_type] || :amen

    if @like.save
      create_notification
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path }
        format.turbo_stream
      end
    else
      redirect_back fallback_location: root_path, alert: "Unable to add reaction."
    end
  end

  def destroy
    @like = current_user.likes.find_by(likeable: @likeable)
    
    if @like&.destroy
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path }
        format.turbo_stream
      end
    else
      redirect_back fallback_location: root_path, alert: "Unable to remove reaction."
    end
  end

  private

  def set_likeable
    @likeable_type = params[:likeable_type].classify
    @likeable_id = params[:likeable_id]
    @likeable = @likeable_type.constantize.find(@likeable_id)
  rescue
    redirect_back fallback_location: root_path, alert: "Invalid content."
  end

  def create_notification
    return if @likeable.user == current_user

    notification_type = @likeable.is_a?(Post) ? :post_liked : :comment_liked

    Notification.create(
      user: @likeable.user,
      actor: current_user,
      notifiable: @like,
      notification_type: notification_type
    )
  end
end


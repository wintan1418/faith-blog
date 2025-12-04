# frozen_string_literal: true

class NotificationsController < ApplicationController
  before_action :authenticate_user!

  def index
    @pagy, @notifications = pagy(current_user.notifications.recent)
  end

  def mark_read
    notification = current_user.notifications.find(params[:id])
    notification.mark_as_read!

    respond_to do |format|
      format.html { redirect_back fallback_location: notifications_path }
      format.turbo_stream
    end
  end

  def mark_all_read
    Notification.mark_all_as_read!(current_user)

    respond_to do |format|
      format.html { redirect_to notifications_path, notice: "All notifications marked as read." }
      format.turbo_stream
    end
  end
end


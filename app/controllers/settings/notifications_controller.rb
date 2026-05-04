# frozen_string_literal: true

module Settings
  class NotificationsController < ApplicationController
    before_action :authenticate_user!

    def edit
      @room_memberships = current_user.room_memberships.includes(:room).order("rooms.name")
    end

    def update
      enabled_ids = Array(params[:room_membership_ids]).map(&:to_i)

      current_user.room_memberships.find_each do |membership|
        membership.update(notifications_enabled: enabled_ids.include?(membership.id))
      end

      redirect_to edit_settings_notifications_path, notice: "Notification settings updated."
    end
  end
end

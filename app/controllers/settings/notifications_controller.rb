# frozen_string_literal: true

module Settings
  class NotificationsController < ApplicationController
    before_action :authenticate_user!

    def edit
      @room_memberships = current_user.room_memberships.includes(:room).order("rooms.name")
      @bible_habit = BibleHabit.for(current_user)
    end

    def update
      enabled_ids = Array(params[:room_membership_ids]).map(&:to_i)
      # An unticked box sends nothing; that means "off" (nil crashed the NOT NULL column).
      current_user.update(email_notifications_enabled: ActiveModel::Type::Boolean.new.cast(params[:email_notifications_enabled]) == true)

      update_feedback_surveys if params.key?(:feedback_surveys)

      current_user.room_memberships.find_each do |membership|
        membership.update(notifications_enabled: enabled_ids.include?(membership.id))
      end

      redirect_to edit_settings_notifications_path, notice: "Notification settings updated."
    end

    private

    # Surveys off = a remembered key on the account (FeedbackCampaign::OPT_OUT_KEY).
    def update_feedback_surveys
      key = FeedbackCampaign::OPT_OUT_KEY
      if params[:feedback_surveys] == "1"
        current_user.update_column(:dismissed_cards, current_user.dismissed_cards - [ key ])
      else
        current_user.dismiss_card!(key)
      end
    end
  end
end

# frozen_string_literal: true

module Settings
  class PrivaciesController < ApplicationController
    before_action :authenticate_user!

    def edit
      @profile = current_user.profile
    end

    def update
      @profile = current_user.profile
      if user_privacy_params.key?(:show_online_status)
        current_user.update_column(:show_online_status, ActiveModel::Type::Boolean.new.cast(user_privacy_params[:show_online_status]) == true)
      end

      if params.dig(:bible, :show_streak).present?
        BibleHabit.for(current_user).update!(show_streak: ActiveModel::Type::Boolean.new.cast(params.dig(:bible, :show_streak)) == true)
      end

      if @profile.update(privacy_params)
        redirect_to edit_settings_privacy_path, notice: "Privacy settings updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def privacy_params
      optional_params(:profile).permit(:public_profile)
    end

    # "Show when I'm online" lives on the user, not the profile.
    def user_privacy_params
      @user_privacy_params ||= optional_params(:user).permit(:show_online_status)
    end
  end
end

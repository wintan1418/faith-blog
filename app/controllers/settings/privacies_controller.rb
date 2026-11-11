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
        current_user.update_column(:show_online_status, ActiveModel::Type::Boolean.new.cast(user_privacy_params[:show_online_status]))
      end

      if @profile.update(privacy_params)
        redirect_to edit_settings_privacy_path, notice: "Privacy settings updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def privacy_params
      params.fetch(:profile, {}).permit(:public_profile)
    end

    # "Show when I'm online" lives on the user, not the profile.
    def user_privacy_params
      @user_privacy_params ||= params.fetch(:user, {}).permit(:show_online_status)
    end
  end
end

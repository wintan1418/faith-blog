# frozen_string_literal: true

module Settings
  class PrivaciesController < ApplicationController
    before_action :authenticate_user!

    def edit
      @profile = current_user.profile
    end

    def update
      @profile = current_user.profile

      if @profile.update(privacy_params)
        redirect_to edit_settings_privacy_path, notice: "Privacy settings updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def privacy_params
      params.require(:profile).permit(:public_profile)
    end
  end
end

# frozen_string_literal: true

module Settings
  # The professional side of a profile: headline, skills, and the lists of
  # experience and education (edited on their own small forms).
  class ProfessionalsController < ApplicationController
    before_action :authenticate_user!

    def edit
      @profile = current_user.profile || current_user.create_profile!
    end

    def update
      @profile = current_user.profile || current_user.create_profile!
      if @profile.update(params.require(:profile).permit(:headline, :skills_list, :assembly))
        redirect_to edit_settings_professional_path, notice: "Professional profile saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end
  end
end

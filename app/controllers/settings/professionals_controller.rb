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
      if @profile.update(params.require(:profile).permit(:headline, :industry, :skills_list, :assembly, :open_to_visibility, open_to: []))
        # Saved: close the page and go back to the professional profile (in
        # the app this closes the screen), like the other settings pages.
        recede_or_redirect_to user_path(current_user.username, tab: "professional"), notice: "Professional profile saved."
      else
        render :edit, status: :unprocessable_entity
      end
    end
  end
end

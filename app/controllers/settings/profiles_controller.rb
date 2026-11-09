# frozen_string_literal: true

class Settings::ProfilesController < ApplicationController
  before_action :authenticate_user!

  def edit
    @profile = current_user.profile
  end

  def update
    @profile = current_user.profile

    if @profile.update(profile_params)
      recede_or_redirect_to user_path(current_user.username), notice: "Profile updated successfully!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:profile).permit(:bio, :location, :faith_background, :website, :public_profile, :avatar,
                                    :birth_month, :birth_day, :birth_year, :show_birthday)
  end
end

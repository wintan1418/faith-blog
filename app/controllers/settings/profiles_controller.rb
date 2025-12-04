# frozen_string_literal: true

class Settings::ProfilesController < ApplicationController
  before_action :authenticate_user!

  def edit
    @profile = current_user.profile
  end

  def update
    @profile = current_user.profile
    
    if @profile.update(profile_params)
      redirect_to settings_profile_path, notice: "Profile updated successfully!"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def profile_params
    params.require(:profile).permit(:bio, :location, :faith_background, :website, :public_profile, :avatar)
  end
end


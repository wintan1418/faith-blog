# frozen_string_literal: true

module Settings
  # On/off for the drifting scripture "rain" in the page background. Saved on
  # the account so it follows the member to every device and the apps.
  class BackgroundRainsController < ApplicationController
    before_action :authenticate_user!

    def update
      on = ActiveModel::Type::Boolean.new.cast(params[:on])
      current_user.update!(background_rain: on)

      respond_to do |format|
        format.json { render json: { on: } }
        format.html do
          redirect_back fallback_location: edit_settings_accent_path,
                        notice: on ? "Background rain is on." : "Background rain is off."
        end
      end
    end
  end
end

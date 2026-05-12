# frozen_string_literal: true

module Settings
  class AccentsController < ApplicationController
    before_action :authenticate_user!

    def edit
      @current = current_user.accent_color.presence || AccentPalette::DEFAULT
    end

    def update
      slug = params[:accent_color].to_s
      slug = AccentPalette::DEFAULT unless AccentPalette.valid?(slug)
      current_user.update!(accent_color: slug)
      redirect_to edit_settings_accent_path, notice: "Accent color updated."
    end
  end
end

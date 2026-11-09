# frozen_string_literal: true

module Settings
  # Languages on the professional profile: added and removed right on the
  # Professional settings page.
  class LanguagesController < ApplicationController
    before_action :authenticate_user!

    def create
      language = current_user.languages.new(params.require(:user_language).permit(:name, :proficiency))
      if language.save
        redirect_to edit_settings_professional_path(anchor: "languages"), notice: "#{language.name} added."
      else
        redirect_to edit_settings_professional_path(anchor: "languages"), alert: language.errors.full_messages.to_sentence
      end
    rescue ArgumentError # an unknown proficiency
      redirect_to edit_settings_professional_path(anchor: "languages"), alert: "Choose a level from the list."
    end

    def destroy
      current_user.languages.find(params[:id]).destroy
      redirect_to edit_settings_professional_path(anchor: "languages"), notice: "Language removed.", status: :see_other
    end
  end
end

# frozen_string_literal: true

module Settings
  class ExperiencesController < ApplicationController
    before_action :authenticate_user!
    before_action :set_experience, only: %i[edit update destroy]

    def new
      @experience = current_user.experiences.new(current: true)
    end

    def create
      @experience = current_user.experiences.new(experience_params)
      if @experience.save
        redirect_to edit_settings_professional_path, notice: "Experience added."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @experience.update(experience_params)
        redirect_to edit_settings_professional_path, notice: "Experience updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @experience.destroy
      redirect_to edit_settings_professional_path, notice: "Experience removed.", status: :see_other
    end

    private

    def set_experience
      @experience = current_user.experiences.find(params[:id])
    end

    def experience_params
      params.require(:experience).permit(:title, :organization, :employment_type, :location,
                                         :start_month, :end_month, :current, :description)
    end
  end
end

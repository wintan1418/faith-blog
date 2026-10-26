# frozen_string_literal: true

module Settings
  class EducationsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_education, only: %i[edit update destroy]

    def new
      @education = current_user.educations.new
    end

    def create
      @education = current_user.educations.new(education_params)
      if @education.save
        redirect_to edit_settings_professional_path, notice: "Education added."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @education.update(education_params)
        redirect_to edit_settings_professional_path, notice: "Education updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @education.destroy
      redirect_to edit_settings_professional_path, notice: "Education removed.", status: :see_other
    end

    private

    def set_education
      @education = current_user.educations.find(params[:id])
    end

    def education_params
      params.require(:education).permit(:school, :qualification, :field_of_study, :start_year, :end_year, :description)
    end
  end
end

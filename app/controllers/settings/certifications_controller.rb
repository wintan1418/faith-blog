# frozen_string_literal: true

module Settings
  # Licenses & certifications on the professional profile.
  class CertificationsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_certification, only: %i[edit update destroy]

    def new
      @certification = current_user.certifications.new
    end

    def create
      @certification = current_user.certifications.new(certification_params)
      if @certification.save
        redirect_to edit_settings_professional_path, notice: "Certification added."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @certification.update(certification_params)
        redirect_to edit_settings_professional_path, notice: "Certification updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @certification.destroy
      redirect_to edit_settings_professional_path, notice: "Certification removed.", status: :see_other
    end

    private

    def set_certification
      @certification = current_user.certifications.find(params[:id])
    end

    def certification_params
      params.require(:certification).permit(:name, :issuer, :issued_month, :expires_month, :credential_url)
    end
  end
end

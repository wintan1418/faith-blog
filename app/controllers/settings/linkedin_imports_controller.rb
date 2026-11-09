# frozen_string_literal: true

module Settings
  # Import from LinkedIn: upload the profile PDF or the data export, review
  # what we found, tick what to add. The file itself is never kept.
  class LinkedinImportsController < ApplicationController
    before_action :authenticate_user!

    def new; end

    def create
      @draft = LinkedinImport.read(params[:file])
      @profile = current_user.profile || current_user.create_profile!
      @have = existing_keys
      render :review
    rescue LinkedinImport::Error => e
      flash.now[:alert] = e.message
      render :new, status: :unprocessable_entity
    end

    def apply
      counts = LinkedinImport::Apply.new(current_user, import_params).call
      if counts.total.zero?
        redirect_to edit_settings_professional_path, notice: "Nothing new to add: your profile already had everything you picked."
      else
        redirect_to user_path(current_user.username, tab: "professional"), notice: "Imported from LinkedIn: #{counts.sentence}."
      end
    end

    private

    def import_params
      return {} unless params[:import].respond_to?(:permit)

      params[:import].permit(:headline, :summary, :industry, :location, :use_headline, :use_summary, :use_industry,
                             :use_location, positions: [], educations: [], certifications: [], languages: [], skills: []).to_h
    end

    # What's already on the profile, so the review page can say "Already added".
    def existing_keys
      {
        roles: current_user.experiences.pluck(:title, :organization).to_set { |t, o| [ MatchKey.for(t), MatchKey.for(o) ] },
        schools: current_user.educations.pluck(:school).to_set(&:downcase),
        certifications: current_user.certifications.pluck(:name).to_set(&:downcase),
        languages: current_user.languages.pluck(:name).to_set(&:downcase),
        skills: @profile.skills.to_set(&:downcase)
      }
    end
  end
end

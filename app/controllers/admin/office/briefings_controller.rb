# frozen_string_literal: true

# The Office briefing: standing context included in every reply.
class Admin::Office::BriefingsController < Admin::Office::BaseController
  def show
    @briefing = OfficeBriefing.current
  end

  def update
    @briefing = OfficeBriefing.current
    if @briefing.update(body: params.dig(:office_briefing, :body).to_s, updated_by: current_user)
      redirect_to admin_office_briefing_path, notice: "Briefing saved. The Office reads it on every reply."
    else
      render :show, status: :unprocessable_entity
    end
  end
end

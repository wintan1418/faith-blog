# frozen_string_literal: true

# A member answering a feedback survey (FeedbackCampaign): the page the alert
# opens, and the feed pop-up's Submit / "Not now" / "Don't ask again".
class FeedbackController < ApplicationController
  before_action :authenticate_user!
  before_action :set_campaign
  before_action :ensure_for_member

  def show
    @response = @campaign.responses.find_by(user_id: current_user.id)
    # Opening it from the alert counts as reading the alert.
    current_user.notifications.unread.where(notifiable: @campaign).update_all(read_at: Time.current)
  end

  def create
    @response = find_or_build_response
    @context = params[:context] == "sheet" ? "sheet" : "page"

    if @response.submitted?
      @saved = true
    elsif !@campaign.live?
      return redirect_to(feedback_survey_path(@campaign), alert: "This survey has closed. Thank you all the same.")
    else
      @saved = @response.submit!(rating: answer_params[:rating], comment: answer_params[:comment],
                                 choice: answer_params[:choice], platform: request_platform)
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          "feedback_#{@campaign.id}_#{@context}",
          partial: @saved ? "feedback/thanks" : "feedback/form",
          locals: { campaign: @campaign, response: @response, context: @context }
        ), status: (@saved ? :ok : :unprocessable_entity)
      end
      format.html do
        if @saved
          redirect_to feedback_survey_path(@campaign)
        else
          render :show, status: :unprocessable_entity
        end
      end
    end
  end

  def snooze
    saved_response.snooze!
    head :no_content
  end

  def decline
    saved_response.decline!
    head :no_content
  end

  private

  def set_campaign
    @campaign = FeedbackCampaign.where.not(launched_at: nil).find_by(id: params[:id])
    render_not_found unless @campaign
  end

  # Members the survey is for, or who already got its alert or answered it.
  def ensure_for_member
    return if performed?
    return if @campaign.responses.exists?(user_id: current_user.id)
    return if current_user.notifications.exists?(notifiable: @campaign)
    return if @campaign.includes_user?(current_user)

    render_not_found
  end

  def render_not_found
    respond_to do |format|
      format.html { redirect_to feed_path, alert: "That survey isn't available." }
      format.any { head :not_found }
    end
  end

  def find_or_build_response
    @campaign.responses.find_or_initialize_by(user_id: current_user.id)
  end

  # The member's row, made if needed (a double tap can race: the second finds the first's).
  def saved_response
    @campaign.responses.find_by(user_id: current_user.id) || @campaign.responses.create!(user_id: current_user.id)
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    @campaign.responses.find_by!(user_id: current_user.id)
  end

  def answer_params
    params.fetch(:feedback, {}).permit(:rating, :comment, :choice)
  end

  def request_platform
    return "web" unless hotwire_native_app?

    request.user_agent.to_s.include?("Android") ? "android_app" : "ios_app"
  end
end

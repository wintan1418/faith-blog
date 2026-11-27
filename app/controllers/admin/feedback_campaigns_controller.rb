# frozen_string_literal: true

require "csv"

# Admin → Feedback: write a survey, launch it (now or scheduled), watch the
# answers come in, export them, close it.
class Admin::FeedbackCampaignsController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_campaign, except: %i[index new create]
  layout "admin"

  PER_PAGE = 50

  def index
    @campaigns = FeedbackCampaign.recent.includes(:created_by)
  end

  def new
    @campaign = FeedbackCampaign.new(
      title: "How is Brethreign working for you?",
      follow_up_prompt: "What should we improve?",
      ends_at: 14.days.from_now.change(min: 0)
    )
  end

  def create
    @campaign = FeedbackCampaign.new(campaign_params.merge(created_by: current_user))
    if @campaign.save
      redirect_to admin_feedback_campaign_path(@campaign), notice: "Survey saved as a draft. Launch it when you're ready."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    redirect_to admin_feedback_campaign_path(@campaign), alert: "A launched survey can't be changed." unless @campaign.draft?
  end

  def update
    return redirect_to(admin_feedback_campaign_path(@campaign), alert: "A launched survey can't be changed.") unless @campaign.draft?

    if @campaign.update(campaign_params)
      redirect_to admin_feedback_campaign_path(@campaign), notice: "Draft updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @campaign.draft?
      @campaign.destroy
      redirect_to admin_feedback_campaigns_path, notice: "Draft deleted."
    else
      redirect_to admin_feedback_campaign_path(@campaign), alert: "Launched surveys are kept. Close it instead."
    end
  end

  def show
    @rating_filter = params[:rating].presence&.to_i
    @rating_filter = nil unless @rating_filter && @campaign.rating_range.cover?(@rating_filter)

    respond_to do |format|
      format.html do
        @audience_size = @campaign.audience_scope.count if @campaign.draft? || @campaign.targeted_count.zero?
        scope = @campaign.answered.includes(user: :profile).newest
        scope = scope.where(rating: @rating_filter) if @rating_filter
        @pagy, @answers = pagy(scope, items: PER_PAGE)
      end
      format.csv do
        send_data csv_for(@campaign), filename: "feedback-#{@campaign.id}-#{Date.current}.csv", type: "text/csv"
      end
    end
  end

  def launch
    if @campaign.launch!
      notice = @campaign.scheduled? ? "Scheduled. It goes out #{@campaign.starts_at.strftime('%b %-d at %-l:%M %p')}." : "Launched. Alerts are going out in batches now."
      redirect_to admin_feedback_campaign_path(@campaign), notice: notice
    else
      redirect_to admin_feedback_campaign_path(@campaign), alert: "This survey can't be launched (already launched, or its end date has passed)."
    end
  end

  def close
    @campaign.close!
    redirect_to admin_feedback_campaign_path(@campaign), notice: "Survey closed. Members won't be asked any more."
  end

  private

  def set_campaign
    @campaign = FeedbackCampaign.find(params[:id])
  end

  def campaign_params
    attrs = params.expect(feedback_campaign: [ :title, :rating_kind, :follow_up_prompt, :choice_question, :choice_options_text,
                                               :audience, :also_push, :also_email, :questions_text, :starts_at, :ends_at ])
    attrs[:choice_options] = attrs.delete(:choice_options_text).to_s.split(/\r?\n/) if attrs.key?(:choice_options_text)
    attrs[:rating_kind] = "stars" unless FeedbackCampaign.rating_kinds.key?(attrs[:rating_kind].to_s)
    attrs[:audience] = "everyone" unless FeedbackCampaign.audiences.key?(attrs[:audience].to_s)
    attrs
  end

  # Spreadsheet apps run cells that start with = + - @ as formulas.
  def safe_cell(value)
    value.to_s.match?(/\A[=+\-@\t\r]/) ? "'#{value}" : value
  end

  def csv_for(campaign)
    CSV.generate do |csv|
      questions = campaign.answer_questions
      csv << [ "Submitted at", "Username", "Rating", campaign.choice_question.presence || "Choice", "Comment", "Platform",
               *questions.map { |q| safe_cell(q["text"]) } ]
      campaign.answered.includes(:user).find_each do |answer|
        csv << [ answer.submitted_at.iso8601, answer.user&.username, answer.rating, safe_cell(answer.choice),
                 safe_cell(answer.comment), answer.platform_label, *questions.map { |q| safe_cell(answer.answer_text(q)) } ]
      end
    end
  end
end

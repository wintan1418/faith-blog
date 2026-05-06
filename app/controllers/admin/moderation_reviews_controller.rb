# frozen_string_literal: true

class Admin::ModerationReviewsController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"
  before_action :set_review, only: [ :show, :decide ]

  ALLOWED_DECISIONS = %w[approve hide warn restrict suspend dismiss].freeze

  def index
    scope = AiModerationReview.includes(:reviewable, :user)

    scope = scope.where(status: filter_statuses) if filter_statuses.present?
    scope = scope.where(severity: params[:severity]) if Ai::Moderation::Policy::SEVERITIES.include?(params[:severity])
    scope = scope.for_category(params[:category]) if params[:category].present?

    scope = scope.order(
      Arel.sql("CASE severity WHEN 'high' THEN 0 WHEN 'medium' THEN 1 WHEN 'low' THEN 2 ELSE 3 END"),
      reviewed_at: :desc
    )

    @pagy, @reviews = pagy(scope, items: 25)
    @counts = {
      pending: AiModerationReview.where(status: :pending).count,
      flagged: AiModerationReview.where(status: :flagged).count,
      high:    AiModerationReview.where(severity: "high", status: %i[pending flagged]).count
    }
  end

  def show
    @recent_logs = ModerationLog.where(target: @review.user).order(created_at: :desc).limit(5) if @review.user
  end

  def decide
    decision = params[:decision].to_s
    notes = params[:notes].to_s

    unless ALLOWED_DECISIONS.include?(decision)
      redirect_to admin_moderation_review_path(@review), alert: "Unknown decision."
      return
    end

    ApplicationRecord.transaction do
      apply_decision!(decision, notes)
      ModerationLog.log_action(
        moderator: current_user,
        action: "ai_review_#{decision}",
        target: @review.reviewable,
        notes: notes,
        metadata: { ai_review_id: @review.id, severity: @review.severity, categories: @review.categories }
      ).update(ai_moderation_review: @review)
    end

    redirect_to admin_moderation_reviews_path, notice: "Review #{decision}d."
  end

  private

  def set_review
    @review = AiModerationReview.find(params[:id])
  end

  def filter_statuses
    case params[:status]
    when "open"     then %w[pending flagged]
    when "decided"  then %w[actioned dismissed cleared]
    when "pending"  then %w[pending]
    when "flagged"  then %w[flagged]
    when "actioned" then %w[actioned]
    when "dismissed" then %w[dismissed]
    when "cleared" then %w[cleared]
    else %w[pending flagged] # default queue view
    end
  end

  def apply_decision!(decision, _notes)
    case decision
    when "approve", "dismiss"
      @review.dismissed!
    when "hide", "warn", "restrict", "suspend"
      @review.actioned!
      apply_user_action!(decision)
    end
  end

  def apply_user_action!(decision)
    profile = @review.user&.risk_profile
    return unless profile

    case decision
    when "warn"
      profile.update!(risk_level: :watch, last_action_at: Time.current) if profile.clear?
    when "restrict"
      profile.update!(risk_level: :restricted, last_action_at: Time.current)
    when "suspend"
      profile.update!(risk_level: :suspended, last_action_at: Time.current)
      @review.user.update(active: false) if @review.user.respond_to?(:active)
    end
  end
end

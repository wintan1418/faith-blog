# frozen_string_literal: true

class Admin::ModerationReviewsController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"
  before_action :set_review, only: [ :show, :decide, :copilot ]

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

    @worker_health = worker_health

    # Held posts with no open review row (gate job lost/crashed before it could
    # write one) are invisible to the queue above — surface them here so a
    # moderator can always find and release every held breath.
    @stuck_posts = Post.where(status: :published, moderation_status: :pending_review)
                       .where.not(id: AiModerationReview.where(reviewable_type: "Post", status: %i[pending flagged])
                                                        .select(:reviewable_id))
                       .includes(:user)
                       .order(created_at: :desc)
                       .limit(50)
  end

  # POST /admin/moderation_reviews/release_post — approve a held post that has
  # no review row to decide through.
  def release_post
    post = Post.find(params[:post_id])
    release_post!(post, decision: "approve")
    redirect_to admin_moderation_reviews_path, notice: "Breath ##{post.id} released to the feed."
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

  def copilot
    op = params[:operation].to_s
    unless Ai::Moderation::Copilot::OPERATIONS.include?(op)
      render plain: "unknown operation", status: :bad_request and return
    end

    @copilot_op     = op
    @copilot_output = Ai::Moderation::Copilot.call(operation: op, review: @review)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to admin_moderation_review_path(@review) }
    end
  rescue Ai::Moderation::Copilot::Error => e
    @copilot_op     = op
    @copilot_output = "Copilot failed: #{e.message}"
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to admin_moderation_review_path(@review), alert: @copilot_output }
    end
  end

  private

  # Live snapshot of the Solid Queue worker so "are background jobs running?"
  # is answerable from the browser instead of SSH. A worker is considered
  # alive when any Solid Queue process heartbeated within the last minute.
  def worker_health
    # table_exists? is a catalog lookup — unlike a failed SELECT it can't
    # abort the surrounding transaction (which would break the rest of the
    # page in environments without Solid Queue tables, e.g. test).
    unless SolidQueue::Process.table_exists?
      return { ok: false, error: "Solid Queue tables not found — queue database not migrated?",
               processes: [], ready: nil, failed: nil, finished_last_hour: nil }
    end

    processes = SolidQueue::Process.order(last_heartbeat_at: :desc).limit(10).to_a
    {
      ok: processes.any? { |p| p.last_heartbeat_at && p.last_heartbeat_at > 1.minute.ago },
      processes: processes,
      ready: SolidQueue::ReadyExecution.count,
      failed: SolidQueue::FailedExecution.count,
      finished_last_hour: SolidQueue::Job.where(finished_at: 1.hour.ago..).count
    }
  rescue StandardError => e
    { ok: false, error: "#{e.class}: #{e.message}", processes: [], ready: nil, failed: nil, finished_last_hour: nil }
  end

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
      release_post_if_post!(decision)
    when "hide", "warn", "restrict", "suspend"
      @review.actioned!
      block_post_if_post!
      apply_user_action!(decision)
    end
  end

  # When the moderator approves/dismisses a Post review, flip the post back to
  # :approved, run the publish-time side effects (fanout, streak), and let the
  # author know it's live now.
  def release_post_if_post!(decision)
    post = @review.reviewable
    return unless post.is_a?(Post)

    release_post!(post, decision: decision)
  end

  def release_post!(post, decision:)
    return if post.moderation_approved?

    post.update_columns(moderation_status: Post.moderation_statuses[:approved], moderation_blocked_reason: nil)
    BreathFanoutJob.perform_later(post.id) if post.published?
    post.user&.bump_breath_streak!

    Notification.create(
      user: post.user,
      actor: current_user,
      notifiable: post,
      notification_type: :post_moderation_approved
    ) if post.user && decision == "approve"
  rescue StandardError => e
    Rails.logger.warn("[ModerationDecide release] #{e.class}: #{e.message}")
  end

  def block_post_if_post!
    post = @review.reviewable
    return unless post.is_a?(Post)
    return if post.moderation_blocked?

    post.update_columns(moderation_status: Post.moderation_statuses[:blocked])
  rescue StandardError => e
    Rails.logger.warn("[ModerationDecide block] #{e.class}: #{e.message}")
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

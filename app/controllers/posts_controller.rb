# frozen_string_literal: true

class PostsController < ApplicationController
  before_action :authenticate_user!, except: [ :index, :show ]
  before_action :set_post, only: [ :show, :edit, :update, :destroy, :feature, :unfeature, :inline_thread,
                                    :join_prayer_chain, :leave_prayer_chain, :mark_prayer_answered ]
  before_action :authorize_post!, only: [ :edit, :update, :destroy ]
  before_action :authorize_feature!, only: [ :feature, :unfeature ]
  before_action :enforce_rate_limit!, only: [ :create ]

  def index
    @pagy, @posts = pagy(
      Post.published.includes(:user, :room, :tags).recent
    )
  end

  def show
    @post.increment_views! unless current_user == @post.user
    @comments = @post.comments.root_comments.active.includes(:user, :replies).oldest_first
    @new_comment = Comment.new
  end

  def new
    @post = current_user.posts.build
    @rooms = Room.public_rooms.ordered
  end

  def create
    @post = current_user.posts.build(post_params)

    if scheduled_in_future?(@post)
      @post.status = :scheduled
      @post.published_at = nil
    end

    verdict = run_post_gatekeeper(@post)
    apply_moderation_verdict(@post, verdict)

    if @post.save
      handle_post_links
      verdict.persist_review!(@post)
      notify_author_of_moderation(@post, verdict) unless verdict.allow?
      redirect_to redirect_target_after_create(@post, verdict),
                  notice: flash_notice_for(verdict, post: @post),
                  alert:  flash_alert_for(verdict)
    else
      @rooms = Room.public_rooms.ordered
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @rooms = Room.public_rooms.ordered
  end

  def update
    if @post.update(post_params)
      handle_post_links
      # Mentions are processed in after_save callback, no need to call again
      redirect_to @post, notice: "Post updated successfully!"
    else
      @rooms = Room.public_rooms.ordered
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @post.destroy
    redirect_to feed_path, notice: "Post deleted successfully."
  end

  def feature
    @post.update(featured: true)
    ModerationLog.log_action(moderator: current_user, action: "featured_post", target: @post)
    redirect_to @post, notice: "Post has been featured."
  end

  def inline_thread
    comments = @post.comments.root_comments.active.includes(:user, :replies).order(created_at: :desc).limit(3)
    render partial: "posts/inline_thread",
           locals: { post: @post, comments: comments, new_comment: Comment.new },
           layout: false
  end

  def unfeature
    @post.update(featured: false)
    ModerationLog.log_action(moderator: current_user, action: "unfeatured_post", target: @post)
    redirect_to @post, notice: "Post has been unfeatured."
  end

  def join_prayer_chain
    return redirect_back(fallback_location: post_path(@post), alert: "This isn't a prayer request.") unless @post.prayer?

    intercession = current_user.prayer_intercessions.find_or_create_by(post: @post)
    if intercession.persisted? && @post.user_id != current_user.id
      Notification.create(user: @post.user, actor: current_user, notifiable: @post, notification_type: :prayer_joined)
    end

    redirect_back fallback_location: post_path(@post), notice: "Praying with you."
  end

  def leave_prayer_chain
    current_user.prayer_intercessions.where(post: @post).destroy_all
    redirect_back fallback_location: post_path(@post), notice: "Removed from chain."
  end

  def mark_prayer_answered
    return redirect_back(fallback_location: post_path(@post), alert: "Only the author can do this.") unless @post.user_id == current_user.id

    @post.update!(prayer_status: :prayer_answered, prayer_answered_at: Time.current)

    intercessor_ids = @post.prayer_intercessions.where.not(user_id: current_user.id).pluck(:user_id)
    intercessor_ids.each do |uid|
      Notification.create(
        user_id: uid,
        actor: current_user,
        notifiable: @post,
        notification_type: :prayer_answered
      )
    end

    redirect_back fallback_location: post_path(@post), notice: "Marked answered. 🌟"
  end

  # Composer assistants — author-facing, never block publish.

  def check_gentleness
    text = composer_text
    return render json: { ok: false, error: "Add a few words first." }, status: :unprocessable_entity if text.length < 20

    result = Ai::Composer::GentlenessCheck.call(content: text)
    render json: {
      ok: true,
      tone: result.tone,
      confidence: result.confidence,
      summary: result.summary,
      nudge: result.nudge,
      suggestion: result.suggestion
    }
  rescue Ai::Composer::GentlenessCheck::ParseError, Ai::Moderation::Client::Error => e
    Rails.logger.warn("[GentlenessCheck] #{e.class}: #{e.message}")
    render json: { ok: false, error: "Couldn't reach the gentleness check. Try again in a moment." }, status: :bad_gateway
  end

  def suggest_scripture
    text = composer_text
    return render json: { ok: false, error: "Add a few sentences first." }, status: :unprocessable_entity if text.length < 40

    result = Ai::Composer::ScriptureSuggester.call(content: text)
    render json: {
      ok: true,
      verses: result.verses.map { |v| { reference: v.reference, reason: v.reason } }
    }
  rescue Ai::Composer::ScriptureSuggester::ParseError, Ai::Moderation::Client::Error => e
    Rails.logger.warn("[ScriptureSuggester] #{e.class}: #{e.message}")
    render json: { ok: false, error: "Couldn't reach the scripture suggester. Try again in a moment." }, status: :bad_gateway
  end

  private

  # Pulls draft text from JSON or form params for the composer assistants.
  # Strips HTML so a Trix-rendered body comes through as plain words.
  def composer_text
    raw = params[:content].to_s
    raw = params.dig(:post, :content).to_s if raw.blank?
    ActionController::Base.helpers.strip_tags(raw).to_s.squish
  end

  def set_post
    @post = Post.friendly.find(params[:id])
  end

  def post_params
    params.require(:post).permit(:title, :content, :room_id, :status, :kind, :prayer_status, :anonymous, :allow_comments, :tag_list, :scheduled_for, images: [])
  end

  def scheduled_in_future?(post)
    post.scheduled_for.present? && post.scheduled_for > Time.current
  end

  def handle_post_links
    return unless params[:linked_post_ids].present?

    # Clear existing links and create new ones
    @post.outbound_links.destroy_all

    linked_ids = params[:linked_post_ids].reject(&:blank?)
    linked_ids.each do |target_id|
      @post.outbound_links.create(target_post_id: target_id, link_type: :related)
    end
  end

  def authorize_post!
    unless @post.user == current_user || current_user_admin?
      redirect_to @post, alert: "You're not authorized to perform this action."
    end
  end

  def authorize_feature!
    unless current_user.admin_or_moderator?
      redirect_to @post, alert: "You're not authorized to perform this action."
    end
  end

  # Synchronous AI gate. Returns a Verdict; never raises (fail-open inside).
  # Drafts and scheduled posts skip the gate — scheduled posts get classified
  # later when ScheduledPostPublisherJob actually publishes them.
  def run_post_gatekeeper(post)
    return Ai::Moderation::PostGatekeeper::Verdict.new(decision: :allow, result: nil) if post.draft? || post.scheduled?

    Ai::Moderation::PostGatekeeper.call(post: post)
  end

  def apply_moderation_verdict(post, verdict)
    case verdict.decision
    when :block
      post.moderation_status = :blocked
      post.moderation_blocked_reason = verdict.reason
    when :hold
      post.moderation_status = :pending_review
      post.moderation_blocked_reason = verdict.reason
    else
      post.moderation_status = :approved
    end
  end

  def notify_author_of_moderation(post, verdict)
    type = verdict.block? ? :post_blocked : :post_held_for_review
    Notification.create(
      user: post.user,
      actor: post.user,
      notifiable: post,
      notification_type: type
    )
  rescue StandardError => e
    Rails.logger.warn("[ModerationNotify] #{e.class}: #{e.message}")
  end

  def redirect_target_after_create(post, verdict)
    return feed_path if verdict.block?

    post
  end

  def flash_notice_for(verdict, post: nil)
    if post&.scheduled?
      return "Scheduled for #{post.scheduled_for.in_time_zone.strftime("%a %b %-d, %l:%M %p")}."
    end

    case verdict.decision
    when :hold then "Your post is held for a moderator to take a look — we do this for delicate topics so we can support the conversation well."
    when :allow then "Posted."
    end
  end

  def flash_alert_for(verdict)
    return nil unless verdict.block?

    "We couldn't publish this — it looks like it crosses our community guidelines. If you believe this is wrong, reply to this message and we'll review."
  end

  # New accounts that have been flagged once or more get rate-limited:
  # at most 3 breaths per hour for the first 24 hours.
  def enforce_rate_limit!
    profile = current_user.risk_profile
    return unless profile

    fresh_account = current_user.created_at && current_user.created_at > 24.hours.ago
    risky = profile.respond_to?(:at_least?) && profile.at_least?(:watch)

    return unless fresh_account && risky

    recent_count = current_user.posts.where("created_at > ?", 1.hour.ago).count
    return if recent_count < 3

    redirect_to feed_path, alert: "Slow down — new accounts are limited to 3 breaths an hour. Try again in a bit."
  end
end

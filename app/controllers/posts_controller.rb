# frozen_string_literal: true

class PostsController < ApplicationController
  before_action :authenticate_user!, except: [ :index, :show ]
  before_action :set_post, only: [ :show, :edit, :update, :destroy, :feature, :unfeature, :reactions, :inline_thread,
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
    # A held breath is invisible to signed-out visitors — including its own
    # author following an email deep link in a browser with no session. Route
    # them through sign-in and back here instead of dead-ending on the
    # "held for moderator review" placeholder.
    if @post.held_for_review? && !user_signed_in?
      store_location_for(:user, request.fullpath)
      return redirect_to new_user_session_path, alert: "Please sign in to view this breath."
    end

    @post.increment_views! unless current_user == @post.user
    @comments = @post.comments.root_comments.active.visible_for(current_user)
                     .includes(:user, :replies, likes: :user).oldest_first
    @new_comment = Comment.new
  end

  # "Who reacted" list for a breath, opened in the shared reactors modal.
  # Grouped by emoji, most-used first, newest reactor first within each group.
  def reactions
    unless @post.visible_to?(current_user)
      head :not_found
      return
    end

    likes = @post.likes.includes(user: { profile: { avatar_attachment: :blob } })
                 .order(created_at: :desc).to_a
    @total_reactions = likes.size
    @reaction_groups = likes.group_by(&:display_emoji)
                            .sort_by { |_emoji, group| -group.size }
  end

  def new
    @post = current_user.posts.build
    # Prefill from a share action. Escaped so the param can only ever
    # contribute plain text.
    if params[:prefill].present?
      @post.content = ERB::Util.html_escape(params[:prefill].to_s.first(500))
    end

    # Game-result share: attaches a game card (rendered as its own block
    # with a play link) plus a warm, non-competitive opening line.
    if params[:share_game].present?
      share = Post.sanitize_game_share(
        "slug" => params[:share_game], "score" => params[:score],
        "total" => params[:total], "streak" => params[:streak], "secs" => params[:secs]
      )
      if share
        @post.game_share = share
        info = Post::GAME_SHARES[share["slug"]]
        @post.content = "Just finished a round of #{info[:name]} — #{share["score"]}/#{share["total"]}. " \
                        "Come play with me and hide some scripture in your heart. 🙌"
      end
    end

    # Lift a comment into a breath of its own: prefill the comment's words
    # (escaped, attributed) and embed the thread it came from so readers can
    # trace it back. The resulting post shares/reshares like any other.
    if params[:from_comment].present?
      comment = Comment.active.find_by(id: params[:from_comment])
      if comment&.moderation_approved? && comment.post.visible_to?(current_user)
        quoted = ERB::Util.html_escape(comment.content.to_plain_text.to_s.strip.first(400))
        @post.content = "💬 A word from @#{comment.user.username} that deserves its own breath:" \
                        "<blockquote>#{quoted}</blockquote>"
        @post.quoted_post = comment.post
      end
    end

    @rooms = Room.public_rooms.ordered
    preload_quoted_post(params[:quote])
  end

  def create
    @post = current_user.posts.build(post_params)
    sanitize_quoted_post!(@post)

    # The composer carries the game card through a hidden JSON field;
    # re-sanitize here — never trust the round trip.
    if params.dig(:post, :game_share).present?
      @post.game_share = Post.sanitize_game_share(params[:post][:game_share])
    end

    if scheduled_in_future?(@post)
      @post.status = :scheduled
      @post.published_at = nil
    end

    # Publish first, moderate async: the breath goes live immediately and
    # AiModerationGateJob (enqueued by the model's create callbacks) classifies
    # it in the background, retro-holding or blocking only when the AI actually
    # flags something. The feed must never depend on a background worker having
    # run — the old born-held flow left every post stuck whenever it didn't.
    @post.moderation_status = :approved

    if @post.save
      handle_post_links
      redirect_to redirect_target_after_create(@post), notice: flash_notice_for(@post)
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
      if @post.draft?
        redirect_to drafts_path, notice: "Draft saved — pick it back up under Drafts when you're ready."
      else
        redirect_to @post, notice: "Post updated successfully!"
      end
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
    comments = @post.comments.root_comments.active.visible_for(current_user)
                    .includes(:user, :replies).order(created_at: :desc).limit(3)
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
    # Hydrate each suggestion with the actual verse text (KJV, cached) so the
    # composer can show the scripture itself instead of just the AI's summary.
    verses = result.verses.map do |v|
      payload = ScriptureLookup.lookup(v.reference) rescue nil
      {
        reference: payload&.dig(:reference).presence || v.reference,
        reason:    v.reason,
        text:      payload&.dig(:text).to_s,
        translation: payload&.dig(:translation).presence || "KJV"
      }
    end
    render json: { ok: true, verses: verses }
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
  rescue ActiveRecord::RecordNotFound
    # Old notification emails carry post URLs baked at send time; once the
    # breath is deleted those links are dead forever. Give signed-in readers
    # a soft landing instead of the bare 404 page. Anonymous requests
    # (crawlers, garbage URLs) still get a proper 404.
    raise unless user_signed_in?

    redirect_to feed_path, alert: "That breath isn't here anymore — it may have been removed."
  end

  def post_params
    params.require(:post).permit(:title, :content, :room_id, :status, :kind, :prayer_status, :anonymous, :allow_comments, :tag_list, :scheduled_for, :voice_note, :voice_duration_ms, :quoted_post_id, images: [])
  end

  # Resolve ?quote=ID for the new-post flow. Only accept posts the viewer is
  # actually allowed to see (drops held / blocked posts silently) and refuse
  # quoting your own breath — that's just a thread, not a quote-repost.
  def preload_quoted_post(id)
    return unless id.present?

    candidate = Post.friendly.find_by(slug: id) || Post.find_by(id: id)
    return unless candidate
    return unless candidate.visible_to?(current_user)
    return if candidate.user_id == current_user.id

    @post.quoted_post = candidate
  end

  # Defence-in-depth at submit time: only allow saving a quoted_post_id that
  # the viewer can actually see and that isn't their own post.
  def sanitize_quoted_post!(post)
    return unless post.quoted_post_id.present?

    target = Post.find_by(id: post.quoted_post_id)
    if target.nil? || !target.visible_to?(current_user) || target.user_id == current_user.id
      post.quoted_post_id = nil
    end
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

  def redirect_target_after_create(post)
    return drafts_path if post.draft?

    post
  end

  def flash_notice_for(post)
    return "Draft saved — find it under Drafts when you're ready to come back." if post.draft?

    if post.scheduled?
      return "Scheduled for #{post.scheduled_for.in_time_zone.strftime("%a %b %-d, %l:%M %p")}."
    end

    "Posted."
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

# frozen_string_literal: true

class UsersController < ApplicationController
  before_action :authenticate_user!, except: [ :show, :posts ]
  before_action :set_user, except: [ :index, :suggested, :mentions ]

  def index
    @query = params[:q].to_s.strip
    @suggestions = user_signed_in? && @query.blank? ? BrethrenSuggestions.for(current_user, limit: 12) : []
    users = User.active.includes(:profile).order(created_at: :desc)

    if @query.present?
      users = users.member_search(@query)
    end

    users = users.where.not(id: current_user.id) if user_signed_in?
    @pagy, @users = pagy(users, items: 24)
  end

  # "See all" from Brethren you may know: every suggestion, as cards with Connect.
  def suggested
    @suggestions = BrethrenSuggestions.for(current_user, limit: 48)
  end

  PROFILE_TABS = %w[breaths professional portfolio about].freeze

  def show
    @profile_private = !profile_visible_to_viewer?(@user)
    # Blocked either way: no breaths here (the page says so, with Unblock).
    @blocked = user_signed_in? && current_user.blocked_user_ids.include?(@user.id)
    @profile_private ||= @blocked
    @tab = PROFILE_TABS.include?(params[:tab]) ? params[:tab] : "breaths"
    @strength = ProfessionalStrength.new(@user) if @tab == "professional" && @user == current_user

    if @profile_private || @tab != "breaths"
      @items = []
      @pagy, @items = pagy_array(@items, items: 20)
      @posts = []
      return
    end

    load_profile_series
    posts    = profile_posts_scope.for_cards.recent.limit(60)
    reshares = Reshare.where(user: @user).includes(:user, post: Post::CARD_INCLUDES)
                      .order(created_at: :desc).limit(60)
    @items = FeedItem.merge(posts: posts, reshares: reshares)
    @pagy, @items = pagy_array(@items, items: 20)
    @posts = @items.map(&:post) # back-compat for any partials still using @posts
  end

  def posts
    @profile_private = !profile_visible_to_viewer?(@user)
    scope = @profile_private ? @user.posts.none : profile_posts_scope
    @pagy, @posts = pagy(scope.for_cards.recent)
    @tab = "breaths"
    @items = @posts.map { |post| FeedItem.from_post(post) }
    render :show
  end

  def mentions
    query = params[:query].to_s.strip.downcase
    suggestions = []

    # Special @everyone token — anyone can use to ping their room
    if query.empty? || "everyone".start_with?(query)
      suggestions << {
        username:   "everyone",
        name:       "Notify everyone in this room",
        avatar_url: nil,
        broadcast:  true
      }
    end

    # Super-admin only @all token — platform-wide ping
    if (current_user.respond_to?(:super_admin?) && current_user.super_admin?) &&
       (query.empty? || "all".start_with?(query))
      suggestions << {
        username:   "all",
        name:       "Notify every member of the platform",
        avatar_url: nil,
        broadcast:  true,
        platform:   true
      }
    end

    if query.length >= 1
      users = User.active.includes(:profile)
                  .where("username ILIKE ?", "%#{query}%")
                  .order(:username)
                  .limit(10)
      suggestions += users.map do |u|
        {
          username:   u.username,
          name:       u.display_name,
          avatar_url: u.profile&.avatar&.attached? ? url_for(u.profile.avatar) : nil
        }
      end
    end

    render json: suggestions
  end

  def follow
    if current_user.follow(@user)
      respond_to do |format|
        format.html { redirect_back fallback_location: user_path(@user.username), notice: "You are now following #{@user.display_name}!" }
        format.turbo_stream
      end
    else
      redirect_back fallback_location: user_path(@user.username), alert: "Unable to follow user."
    end
  end

  def unfollow
    if current_user.unfollow(@user)
      respond_to do |format|
        format.html { redirect_back fallback_location: user_path(@user.username), notice: "You unfollowed #{@user.display_name}." }
        format.turbo_stream
      end
    else
      redirect_back fallback_location: user_path(@user.username), alert: "Unable to unfollow user."
    end
  end

  def followers
    return redirect_private_profile unless profile_visible_to_viewer?(@user)

    @pagy, @users = pagy(@user.followers.includes(:profile), items: 24)
  end

  def following
    return redirect_private_profile unless profile_visible_to_viewer?(@user)

    @pagy, @users = pagy(@user.following.includes(:profile), items: 24)
  end

  private

  def set_user
    # Usernames keep their capitals ("Victoria"), but links and @mentions often arrive lower-case.
    @user = User.find_by(username: params[:username]) ||
            User.where("LOWER(username) = ?", params[:username].to_s.downcase).first!
  end

  def redirect_private_profile
    redirect_to user_path(@user.username), alert: "This profile is private."
  end

  # A private profile (public_profile = false) hides its posts from everyone
  # except the owner and admins/moderators.
  # Anonymous breaths never appear on (or count toward) their author's
  # profile — that would unmask them. The author still sees their own.
  def profile_posts_scope
    # Posts written as a page belong to the page, not the writer's profile.
    scope = @user.posts.published.personal
    user_signed_in? && current_user == @user ? scope : scope.where(anonymous: false)
  end

  # The "Series" row above the breaths: series with a part this viewer may
  # read, with how many. The member sees all of their own.
  def load_profile_series
    own = user_signed_in? && current_user == @user
    parts = own ? Post.where(user: @user) : Post.series_listable
    @series_part_counts = parts.where(series_id: @user.series.select(:id)).group(:series_id).count
    @profile_series = @user.series.where(id: @series_part_counts.keys).order(updated_at: :desc).to_a
  end

    def profile_visible_to_viewer?(user)
    return true if user.profile&.public_profile? != false
    return false unless user_signed_in?

    current_user == user || current_user.admin_or_moderator?
  end
end

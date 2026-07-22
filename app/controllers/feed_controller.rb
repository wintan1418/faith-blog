# frozen_string_literal: true

class FeedController < ApplicationController
  before_action :authenticate_user!
  before_action :load_sidebar_context

  POSTS_BUFFER    = 60
  RESHARES_BUFFER = 60
  PER_PAGE        = 20

  def index
    # Pinned breaths (admin-featured) lead the feed — a community noticeboard.
    @pinned_posts = feed_posts_scope.where(featured: true).recent.limit(2).to_a

    posts    = feed_posts_scope.where.not(id: @pinned_posts.map(&:id)).recent.limit(POSTS_BUFFER)
    reshares = Reshare.includes(:user, post: feed_post_includes)
                      .order(created_at: :desc)
                      .limit(RESHARES_BUFFER)

    @pagy, @items = pagy_array(FeedItem.merge(posts: posts, reshares: reshares), items: PER_PAGE)
    respond_to_feed
  end

  def threads
    posts = Post.published
                .threads_or_active
                .includes(feed_post_includes)
                .recent
                .limit(POSTS_BUFFER)

    @pagy, @items = pagy_array(posts.map { |p| FeedItem.from_post(p) }, items: PER_PAGE)
    respond_to_feed
  end

  def trending
    posts = feed_posts_scope
                .where("published_at > ?", 7.days.ago)
                .order(Arel.sql("(likes_count * 2 + comments_count * 3 + views_count * 0.1) DESC"))
                .limit(POSTS_BUFFER)

    @pagy, @items = pagy_array(posts.map { |p| FeedItem.from_post(p) }, items: PER_PAGE)
    respond_to_feed
  end

  def following
    followed_user_ids = current_user.following.pluck(:id)

    posts    = feed_posts_scope
                   .where(user_id: followed_user_ids)
                   .recent
                   .limit(POSTS_BUFFER)
    reshares = Reshare.includes(:user, post: feed_post_includes)
                      .where(user_id: followed_user_ids)
                      .order(created_at: :desc)
                      .limit(RESHARES_BUFFER)

    @pagy, @items = pagy_array(FeedItem.merge(posts: posts, reshares: reshares), items: PER_PAGE)
    respond_to_feed
  end

  private

  def feed_posts_scope
    Post.published.includes(feed_post_includes)
  end

  def feed_post_includes
    [ :user, :room, :tags, :rich_text_content, { likes: :user } ]
  end

  def respond_to_feed
    respond_to do |format|
      format.html { render :index }
      format.turbo_stream { render :paginate }
    end
  end

  def load_sidebar_context
    @prayer_room = Room.prayers.public_rooms.ordered.first
    prayer_room_ids = Room.prayers.select(:id)
    prayer_posts = Post.published
                       .where(room_id: prayer_room_ids)
                       .includes(:user, :room)
                       .recent

    @open_prayer_requests_count = prayer_posts.count
    @open_prayer_requests = prayer_posts.limit(3)

    @daily_verses  = BibleVerse.active.ordered.limit(20).to_a
    @daily_breaths = GoldenBreath.active.ordered.limit(20).to_a
    @user_reading_plan = current_user.user_reading_plans.where(completed: false).order(updated_at: :desc).first

    @trending_breaths = Post.published
                            .where("published_at > ?", 7.days.ago)
                            .includes(:user, :room)
                            .order(Arel.sql("(likes_count * 2 + comments_count * 3 + views_count * 0.1) DESC"))
                            .limit(4)

    following_ids = current_user.following.pluck(:id) << current_user.id
    active_author_ids = Post.published
                            .where("published_at > ?", 30.days.ago)
                            .where.not(user_id: following_ids)
                            .group(:user_id)
                            .order(Arel.sql("COUNT(*) DESC"))
                            .limit(3)
                            .pluck(:user_id)
    @who_to_brethren = User.where(id: active_author_ids).includes(:profile).to_a

    # Fallback: if no recent authors among non-followed, show 3 newest
    # active members so the widget never disappears.
    if @who_to_brethren.size < 3
      need = 3 - @who_to_brethren.size
      already_ids = following_ids + @who_to_brethren.map(&:id)
      fillers = User.respond_to?(:active) ? User.active : User.all
      fillers = fillers.where.not(id: already_ids).order(created_at: :desc).limit(need).includes(:profile)
      @who_to_brethren += fillers.to_a
    end

    # Brand-new users see an onboarding card: no posts, no follows. Once they
    # take their first action the condition flips and the card stops rendering.
    @show_onboarding = current_user.posts.none? && current_user.following.empty?
    @onboarding_rooms = Room.public_rooms.ordered.limit(3) if @show_onboarding

    @release_announcement = Announcement.latest_release
    @new_member_announcements = Announcement.recent_new_members(limit: 4)
  end
end

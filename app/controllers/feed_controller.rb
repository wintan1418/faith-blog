# frozen_string_literal: true

class FeedController < ApplicationController
  before_action :authenticate_user!
  before_action :load_sidebar_context

  POSTS_BUFFER    = 60
  RESHARES_BUFFER = 60
  PER_PAGE        = 20

  def index
    posts    = Post.published.includes(:user, :room, :tags).recent.limit(POSTS_BUFFER)
    reshares = Reshare.includes(:user, post: [ :user, :room, :tags ])
                      .order(created_at: :desc)
                      .limit(RESHARES_BUFFER)

    @pagy, @items = pagy_array(FeedItem.merge(posts: posts, reshares: reshares), items: PER_PAGE)
  end

  def threads
    posts = Post.published
                .threads_or_active
                .includes(:user, :room, :tags)
                .recent
                .limit(POSTS_BUFFER)

    @pagy, @items = pagy_array(posts.map { |p| FeedItem.from_post(p) }, items: PER_PAGE)
    render :index
  end

  def trending
    posts = Post.published
                .includes(:user, :room, :tags)
                .where("published_at > ?", 7.days.ago)
                .order(Arel.sql("(likes_count * 2 + comments_count * 3 + views_count * 0.1) DESC"))
                .limit(POSTS_BUFFER)

    @pagy, @items = pagy_array(posts.map { |p| FeedItem.from_post(p) }, items: PER_PAGE)
    render :index
  end

  def following
    followed_user_ids = current_user.following.pluck(:id)

    posts    = Post.published
                   .includes(:user, :room, :tags)
                   .where(user_id: followed_user_ids)
                   .recent
                   .limit(POSTS_BUFFER)
    reshares = Reshare.includes(:user, post: [ :user, :room, :tags ])
                      .where(user_id: followed_user_ids)
                      .order(created_at: :desc)
                      .limit(RESHARES_BUFFER)

    @pagy, @items = pagy_array(FeedItem.merge(posts: posts, reshares: reshares), items: PER_PAGE)
    render :index
  end

  private

  def load_sidebar_context
    @prayer_room = Room.prayers.public_rooms.ordered.first
    prayer_room_ids = Room.prayers.select(:id)
    prayer_posts = Post.published
                       .where(room_id: prayer_room_ids)
                       .includes(:user, :room)
                       .recent

    @open_prayer_requests_count = prayer_posts.count
    @open_prayer_requests = prayer_posts.limit(3)

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
    @who_to_brethren = User.where(id: active_author_ids).includes(:profile)
  end
end

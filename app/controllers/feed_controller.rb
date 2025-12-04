# frozen_string_literal: true

class FeedController < ApplicationController
  before_action :authenticate_user!

  def index
    @pagy, @posts = pagy(
      Post.published
          .includes(:user, :room, :tags)
          .recent
    )
  end

  def trending
    @pagy, @posts = pagy(
      Post.published
          .includes(:user, :room, :tags)
          .where("published_at > ?", 7.days.ago)
          .order(Arel.sql("(likes_count * 2 + comments_count * 3 + views_count * 0.1) DESC"))
    )
    render :index
  end

  def following
    followed_user_ids = current_user.following.pluck(:id)
    @pagy, @posts = pagy(
      Post.published
          .where(user_id: followed_user_ids)
          .includes(:user, :room, :tags)
          .recent
    )
    render :index
  end
end


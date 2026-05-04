# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    if user_signed_in?
      redirect_to feed_path
    else
      @rooms = Room.public_rooms.ordered.limit(8)
      @featured_rooms = @rooms.first(4)
      @posts = Post.published.includes(:user, :room, :tags).recent.limit(8)
      @prayer_posts = Post.published
                          .where(room_id: Room.prayers.public_rooms.select(:id))
                          .includes(:user, :room)
                          .recent
                          .limit(3)
      @trending_posts = Post.published
                            .includes(:user, :room)
                            .order(Arel.sql("(likes_count * 2 + comments_count * 3 + views_count * 0.1) DESC"))
                            .limit(4)
      @resources = Resource.approved.featured.includes(:resource_category).recent.limit(4)
    end
  end
end

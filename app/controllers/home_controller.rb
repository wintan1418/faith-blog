# frozen_string_literal: true

class HomeController < ApplicationController
  def index
    if user_signed_in?
      redirect_to feed_path
    else
      @rooms = Room.public_rooms.ordered.limit(6)
      @featured_posts = Post.published.featured.includes(:user, :room).limit(3)
    end
  end
end


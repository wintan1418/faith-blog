# frozen_string_literal: true

class HomeController < ApplicationController
  # Signed-out web visitors get a welcome page at "/" (brand, Join, Sign in).
  # The public feed is still one tap away at "/?browse=1" ("Look around first"),
  # and the apps keep opening "/" straight into it.
  def index
    if user_signed_in?
      redirect_to feed_path
    elsif !hotwire_native_app? && params[:browse].blank?
      # Always the web page: bots and link checkers sometimes ask "/" for JSON.
      render :welcome, formats: :html, content_type: "text/html"
    else
      @rooms = Room.public_rooms.ordered.limit(8)
      @featured_rooms = @rooms.first(4)
      # Same author mix as the signed-in feed, so one busy author can't fill the guest view.
      recent = Post.published.recent.limit(200).pluck(:id, :published_at, :user_id)
      entries = recent.map { |id, at, uid| { kind: :post, id: id, at: at, author_id: uid } }
      ids = FeedMix.call(entries, seed: "guest:#{Date.current}").first(8).map { |e| e[:id] }
      @posts = Post.where(id: ids).includes(:user, :room, :tags).index_by(&:id).values_at(*ids).compact
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

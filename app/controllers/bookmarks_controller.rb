# frozen_string_literal: true

class BookmarksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_post

  def index
    @pagy, @posts = pagy(current_user.bookmarked_posts.includes(:user, :room).recent)
  end

  def create
    @bookmark = current_user.bookmarks.find_or_initialize_by(post: @post)

    if @bookmark.save
      respond_to do |format|
        format.html { redirect_back fallback_location: @post, notice: "Post bookmarked!" }
        format.turbo_stream
      end
    else
      redirect_back fallback_location: @post, alert: "Unable to bookmark post."
    end
  end

  def destroy
    @bookmark = current_user.bookmarks.find_by(post: @post)

    if @bookmark&.destroy
      respond_to do |format|
        format.html { redirect_back fallback_location: @post, notice: "Bookmark removed." }
        format.turbo_stream
      end
    else
      redirect_back fallback_location: @post, alert: "Unable to remove bookmark."
    end
  end

  private

  def set_post
    return unless params[:post_id]

    @post = Post.friendly.find(params[:post_id])
    return if @post.visible_to?(current_user)

    redirect_back fallback_location: root_path, alert: "That post isn't available."
  end
end

# frozen_string_literal: true

class Admin::PostsController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"
  before_action :set_post, only: [:show, :edit, :update, :destroy, :feature, :unfeature]

  def index
    @posts = Post.includes(:user, :room).order(created_at: :desc).page(params[:page]).per(20)
  end

  def show
  end

  def edit
  end

  def update
    if @post.update(post_params)
      redirect_to admin_post_path(@post), notice: "Post updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @post.destroy
    ModerationLog.log_action(moderator: current_user, action: "deleted_post", target: @post)
    redirect_to admin_posts_path, notice: "Post deleted."
  end

  def feature
    @post.update(featured: true)
    ModerationLog.log_action(moderator: current_user, action: "featured_post", target: @post)
    redirect_to admin_post_path(@post), notice: "Post featured."
  end

  def unfeature
    @post.update(featured: false)
    ModerationLog.log_action(moderator: current_user, action: "unfeatured_post", target: @post)
    redirect_to admin_post_path(@post), notice: "Post unfeatured."
  end

  private

  def set_post
    @post = Post.find(params[:id])
  end

  def post_params
    params.require(:post).permit(:title, :status, :featured, :room_id)
  end
end


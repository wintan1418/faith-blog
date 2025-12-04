# frozen_string_literal: true

class PostsController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_post, only: [:show, :edit, :update, :destroy, :feature, :unfeature]
  before_action :authorize_post!, only: [:edit, :update, :destroy]
  before_action :authorize_feature!, only: [:feature, :unfeature]

  def index
    @pagy, @posts = pagy(
      Post.published.includes(:user, :room, :tags).recent
    )
  end

  def show
    @post.increment_views! unless current_user == @post.user
    @comments = @post.comments.root_comments.active.includes(:user, :replies).oldest_first
    @new_comment = Comment.new
  end

  def new
    @post = current_user.posts.build
    @rooms = Room.public_rooms.ordered
  end

  def create
    @post = current_user.posts.build(post_params)
    
    if @post.save
      redirect_to @post, notice: "Post created successfully!"
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
      redirect_to @post, notice: "Post updated successfully!"
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

  def unfeature
    @post.update(featured: false)
    ModerationLog.log_action(moderator: current_user, action: "unfeatured_post", target: @post)
    redirect_to @post, notice: "Post has been unfeatured."
  end

  private

  def set_post
    @post = Post.friendly.find(params[:id])
  end

  def post_params
    params.require(:post).permit(:title, :content, :room_id, :status, :anonymous, :allow_comments, :tag_list)
  end

  def authorize_post!
    unless @post.user == current_user || current_user.admin?
      redirect_to @post, alert: "You're not authorized to perform this action."
    end
  end

  def authorize_feature!
    unless current_user.admin_or_moderator?
      redirect_to @post, alert: "You're not authorized to perform this action."
    end
  end
end


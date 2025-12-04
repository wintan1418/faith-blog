# frozen_string_literal: true

class UsersController < ApplicationController
  before_action :authenticate_user!, except: [:show, :posts]
  before_action :set_user

  def show
    @pagy, @posts = pagy(@user.posts.published.includes(:room, :tags).recent)
  end

  def posts
    @pagy, @posts = pagy(@user.posts.published.includes(:room, :tags).recent)
    render :show
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
    @pagy, @users = pagy(@user.followers.includes(:profile))
  end

  def following
    @pagy, @users = pagy(@user.following.includes(:profile))
  end

  private

  def set_user
    @user = User.find_by!(username: params[:username])
  end
end


# frozen_string_literal: true

class UsersController < ApplicationController
  before_action :authenticate_user!, except: [ :show, :posts ]
  before_action :set_user, except: [ :index, :mentions ]

  def index
    @query = params[:q].to_s.strip
    users = User.active.includes(:profile).order(created_at: :desc)

    if @query.present?
      users = users
        .left_joins(:profile)
        .where(
          "users.username ILIKE :query OR users.email ILIKE :query OR profiles.bio ILIKE :query OR profiles.location ILIKE :query OR profiles.faith_background ILIKE :query",
          query: "%#{@query}%"
        )
    end

    users = users.where.not(id: current_user.id) if user_signed_in?
    @pagy, @users = pagy(users, items: 24)
  end

  def show
    posts    = @user.posts.published.includes(:room, :tags).recent.limit(60)
    reshares = Reshare.where(user: @user).includes(post: [ :user, :room, :tags ])
                      .order(created_at: :desc).limit(60)
    @items = FeedItem.merge(posts: posts, reshares: reshares)
    @pagy, @items = pagy_array(@items, items: 20)
    @posts = @items.map(&:post) # back-compat for any partials still using @posts
  end

  def posts
    @pagy, @posts = pagy(@user.posts.published.includes(:room, :tags).recent)
    render :show
  end

  def mentions
    query = params[:query].to_s.strip
    return render json: [] if query.length < 1

    users = User
      .active
      .includes(:profile)
      .where("username ILIKE ?", "%#{query}%")
      .order(:username)
      .limit(10)

    render json: users.map { |u|
      {
        username: u.username,
        name: u.display_name,
        avatar_url: u.profile&.avatar&.attached? ? url_for(u.profile.avatar) : nil
      }
    }
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

# frozen_string_literal: true

class Admin::UsersController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"
  before_action :set_user, only: [ :show, :edit, :update, :destroy, :suspend, :activate, :make_moderator, :make_admin ]

  FILTERS = {
    "all" => "All", "online" => "Online now", "active" => "Active in 7 days", "new" => "Joined this week",
    "android" => "Android app", "suspended" => "Suspended"
  }.freeze

  def index
    @filter = FILTERS.key?(params[:filter]) ? params[:filter] : "all"
    @query = params[:q].to_s.strip
    scope = filtered(User.includes(:profile))
    if @query.present?
      like = "%#{User.sanitize_sql_like(@query)}%"
      scope = scope.where("users.username ILIKE :q OR users.email ILIKE :q", q: like)
    end
    @total = User.count
    @matching = scope.count
    @counts = FILTERS.keys.index_with { |key| filtered(User.all, key).count }
    @pagy, @users = pagy(scope.order(created_at: :desc), items: 25)
  end

  def show
  end

  def edit
  end

  def update
    if @user.update(user_params)
      redirect_to admin_user_path(@user), notice: "User updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @user.destroy
    redirect_to admin_users_path, notice: "User deleted."
  end

  def suspend
    @user.update(active: false)
    ModerationLog.log_action(moderator: current_user, action: "suspended_user", target: @user)
    redirect_to admin_user_path(@user), notice: "User suspended."
  end

  def activate
    @user.update(active: true)
    ModerationLog.log_action(moderator: current_user, action: "activated_user", target: @user)
    redirect_to admin_user_path(@user), notice: "User activated."
  end

  def make_moderator
    @user.update(role: :moderator)
    ModerationLog.log_action(moderator: current_user, action: "promoted_to_moderator", target: @user)
    redirect_to admin_user_path(@user), notice: "User promoted to moderator."
  end

  def make_admin
    @user.update(role: :admin)
    ModerationLog.log_action(moderator: current_user, action: "promoted_to_admin", target: @user)
    redirect_to admin_user_path(@user), notice: "User promoted to admin."
  end

  private

  def filtered(scope, key = @filter)
    case key
    when "online" then scope.online
    when "active" then scope.where(last_seen_at: 7.days.ago..)
    when "new" then scope.where(created_at: Time.current.in_time_zone(AdminDashboardStats::TZ).beginning_of_week..)
    when "android" then scope.where.not(android_app_version: nil)
    when "suspended" then scope.where(active: false)
    else scope
    end
  end

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:username, :email)
  end
end

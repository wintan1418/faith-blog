# frozen_string_literal: true

class Admin::UsersController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"
  before_action :set_user, only: [:show, :edit, :update, :destroy, :suspend, :activate, :make_moderator, :make_admin]

  def index
    @users = User.includes(:profile).order(created_at: :desc).page(params[:page]).per(20)
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

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:username, :email, :role, :active)
  end
end


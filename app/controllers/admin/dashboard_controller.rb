# frozen_string_literal: true

class Admin::DashboardController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"

  def index
    @total_users = User.count
    @new_users_today = User.where("created_at >= ?", Time.current.beginning_of_day).count
    @total_posts = Post.count
    @posts_today = Post.where("created_at >= ?", Time.current.beginning_of_day).count
    @pending_reports = Report.pending.count
    @pending_resources = Resource.pending.count
    @recent_posts = Post.includes(:user, :room).order(created_at: :desc).limit(5)
    @recent_users = User.includes(:profile).order(created_at: :desc).limit(5)
  end
end


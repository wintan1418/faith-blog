# frozen_string_literal: true

class Admin::UsersController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"
  before_action :set_user, only: [ :show, :edit, :update, :destroy, :suspend, :activate, :make_moderator, :make_admin,
                                   :security, :resend_verification, :reset_two_factor ]
  # Role changes and deleting accounts are for super admins only; and nobody
  # can act on themselves or on someone of equal or higher rank.
  before_action :require_super_admin!, only: [ :destroy, :make_moderator, :make_admin ]
  before_action :require_outranks_target!, only: [ :edit, :update, :destroy, :suspend, :activate, :make_moderator, :make_admin,
                                                   :reset_two_factor ]

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

  # Everything about one member, for admins: account, profile (public or not),
  # activity and recent breaths. Actions stay on the list and Security pages.
  def show
    @profile = @user.profile
    @recent_posts = @user.posts.order(created_at: :desc).limit(8)
    @stats = {
      "Breaths" => @user.posts.count, "Comments" => @user.comments.count,
      "Followers" => @user.followers_count, "Following" => @user.following_count,
      "Rooms" => @user.rooms.count, "Seeds" => @user.seeds_total.to_i,
      "Reports made" => @user.reports.count, "Reports about them" => @user.reports_about.count
    }
  end

  def edit
    redirect_to admin_users_path(q: @user.username)
  end

  def update
    if @user.update(user_params)
      redirect_to admin_user_path(@user), notice: "User updated successfully."
    else
      redirect_to admin_users_path(q: @user.username_was), alert: @user.errors.full_messages.to_sentence
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

  # Account security for one member: verification, two-step login, devices
  # and recent sign-ins (approximate place only).
  def security
    @devices = @user.user_devices.by_recent.limit(20)
    @events = @user.security_events.recent.includes(:actor).limit(40)
    @sign_ins = @user.security_events.sign_ins.recent.limit(10)
  end

  # Emails the member a fresh verification code (to their own address only).
  def resend_verification
    if @user.email_verified?
      return redirect_to(security_admin_user_path(@user), notice: "#{@user.username}'s email is already verified.")
    end

    EmailVerification.send_code!(@user)
    SecurityEvent.record!(:admin_resent_verification, user: @user, actor: current_user, request: request)
    ModerationLog.log_action(moderator: current_user, action: "resent_email_verification", target: @user)
    redirect_to security_admin_user_path(@user), notice: "A new verification code is on its way to #{@user.masked_email}."
  rescue SecurityCode::RateLimited => e
    redirect_to security_admin_user_path(@user), alert: e.message
  end

  # For a member who lost their phone and recovery codes (after checking it's
  # really them). They're emailed about it.
  def reset_two_factor
    unless @user.two_factor_enabled?
      return redirect_to(security_admin_user_path(@user), notice: "Two-step login is already off for #{@user.username}.")
    end

    @user.disable_two_factor!
    SecurityEvent.record!(:admin_reset_two_factor, user: @user, actor: current_user, request: request)
    ModerationLog.log_action(moderator: current_user, action: "reset_two_factor", target: @user,
                             notes: params[:reason].to_s.strip.first(500).presence)
    AccountSecurityMailer.with(user: @user, by_admin: true).two_factor_disabled.deliver_later
    redirect_to security_admin_user_path(@user), notice: "Two-step login is off for #{@user.username}. They've been emailed."
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

  # Only a super admin may change someone's email (it's how accounts are recovered).
  def user_params
    permitted = current_user.super_admin? ? [ :username, :email ] : [ :username ]
    params.expect(user: [ *permitted ])
  end

  def require_super_admin!
    return if current_user.super_admin?

    redirect_to admin_users_path, alert: "Only a super admin can do that."
  end

  def require_outranks_target!
    return if current_user.outranks?(@user)

    redirect_to admin_users_path, alert: "You can't change an account of equal or higher rank."
  end
end

# frozen_string_literal: true

class CirclesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_circle, only: [ :show, :destroy, :leave, :rotate_invite ]
  before_action :require_membership!, only: [ :show ]
  before_action :require_owner!, only: [ :destroy, :rotate_invite ]

  def index
    @circles = current_user.circles
                           .left_joins(:breaths)
                           .select("circles.*, MAX(circle_breaths.created_at) AS last_breath_at")
                           .group("circles.id")
                           .order(Arel.sql("MAX(circle_breaths.created_at) DESC NULLS LAST"))
    @new_circle = Circle.new
  end

  def show
    @breaths       = @circle.breaths.recent.includes(user: { profile: { avatar_attachment: :blob } }).limit(200)
    @open_prayers  = @circle.prayers.prayer_open.recent.includes(:user)
    @answered_prayers = @circle.prayers.prayer_answered.order(answered_at: :desc).limit(10).includes(:user)
    @members       = @circle.members.includes(profile: { avatar_attachment: :blob })
  end

  def create
    @circle = Circle.new(circle_params.merge(owner: current_user))
    if @circle.save
      @circle.circle_memberships.create!(user: current_user, role: :owner)
      redirect_to circle_path(@circle), notice: "“#{@circle.name}” is gathered. Share the invite link to bring your people in."
    else
      redirect_to circles_path, alert: @circle.errors.full_messages.to_sentence
    end
  end

  def join
    circle = Circle.find_by(invite_code: params[:code])
    if circle.nil?
      redirect_to circles_path, alert: "That invite link is no longer valid."
    elsif circle.member?(current_user)
      redirect_to circle_path(circle)
    else
      circle.circle_memberships.create!(user: current_user)
      redirect_to circle_path(circle), notice: "Welcome into “#{circle.name}”. 🕊️"
    end
  end

  def leave
    if @circle.owned_by?(current_user)
      redirect_to circle_path(@circle), alert: "Owners can't leave their circle — delete it instead, or hand it over."
    else
      @circle.circle_memberships.find_by(user: current_user)&.destroy
      redirect_to circles_path, notice: "You've left “#{@circle.name}”."
    end
  end

  def destroy
    @circle.destroy
    redirect_to circles_path, notice: "“#{@circle.name}” has been dissolved."
  end

  def rotate_invite
    @circle.rotate_invite_code!
    redirect_to circle_path(@circle), notice: "New invite link issued — the old one no longer works."
  end

  private

  def set_circle
    @circle = Circle.find_by!(slug: params[:slug])
  end

  def require_membership!
    return if @circle.member?(current_user)

    redirect_to circles_path, alert: "That circle is private."
  end

  def require_owner!
    return if @circle.owned_by?(current_user)

    redirect_to circle_path(@circle), alert: "Only the circle owner can do that."
  end

  def circle_params
    params.require(:circle).permit(:name, :description)
  end
end

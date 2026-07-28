# frozen_string_literal: true

class CirclePrayersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_circle_and_require_membership!
  before_action :set_prayer, only: [ :destroy, :amen, :answered ]

  def create
    prayer = @circle.prayers.build(prayer_params.merge(user: current_user))
    if prayer.save
      redirect_to circle_path(@circle), notice: "Added to the prayer list. The circle has been told. 🙏"
    else
      redirect_to circle_path(@circle), alert: prayer.errors.full_messages.to_sentence
    end
  end

  def destroy
    unless @prayer.user_id == current_user.id || @circle.owned_by?(current_user)
      return redirect_to circle_path(@circle), alert: "You can only remove prayers you added."
    end

    @prayer.destroy
    redirect_to circle_path(@circle), notice: "Prayer removed from the list."
  end

  # Toggle "I prayed" on a list entry.
  def amen
    existing = @prayer.amens.find_by(user: current_user)
    if existing
      existing.destroy
    else
      @prayer.amens.create!(user: current_user)
    end
    redirect_to circle_path(@circle)
  end

  def answered
    unless @prayer.user_id == current_user.id || @circle.owned_by?(current_user)
      return redirect_to circle_path(@circle), alert: "Only the one who asked (or the owner) can mark it answered."
    end

    @prayer.mark_answered!(by: current_user)
    redirect_to circle_path(@circle), notice: "Marked answered — the circle rejoices with you. 🌟"
  end

  private

  def set_circle_and_require_membership!
    @circle = Circle.find_by!(slug: params[:circle_slug])
    redirect_to circles_path, alert: "That circle is private." unless @circle.member?(current_user)
  end

  def set_prayer
    @prayer = @circle.prayers.find(params[:id])
  end

  def prayer_params
    params.require(:circle_prayer).permit(:title, :details)
  end
end

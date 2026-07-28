# frozen_string_literal: true

class CircleBreathsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_circle_and_require_membership!

  def create
    breath = @circle.breaths.build(user: current_user, body: params.dig(:circle_breath, :body))
    if breath.save
      redirect_to circle_path(@circle), notice: "Breathed."
    else
      redirect_to circle_path(@circle), alert: breath.errors.full_messages.to_sentence
    end
  end

  def destroy
    breath = @circle.breaths.find(params[:id])
    unless breath.user_id == current_user.id || @circle.owned_by?(current_user)
      return redirect_to circle_path(@circle), alert: "You can only remove your own breaths."
    end

    breath.destroy
    redirect_to circle_path(@circle), notice: "Breath removed."
  end

  private

  def set_circle_and_require_membership!
    @circle = Circle.find_by!(slug: params[:circle_slug])
    redirect_to circles_path, alert: "That circle is private." unless @circle.member?(current_user)
  end
end

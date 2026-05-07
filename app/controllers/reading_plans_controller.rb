# frozen_string_literal: true

class ReadingPlansController < ApplicationController
  before_action :authenticate_user!
  before_action :set_plan, only: [ :show, :start, :check_in, :leave ]

  def index
    @plans = ReadingPlan.all
    @user_plans = current_user.user_reading_plans.index_by(&:plan_slug)
  end

  def show
    @user_plan = current_user.user_reading_plans.find_by(plan_slug: @plan.slug)
  end

  def start
    user_plan = current_user.user_reading_plans.find_or_initialize_by(plan_slug: @plan.slug)
    if user_plan.new_record?
      user_plan.assign_attributes(current_day: 1, started_on: Date.current, completed: false)
      user_plan.save!
    end
    redirect_to reading_plan_path(@plan.slug), notice: "Plan started. Day 1 is up."
  end

  def check_in
    user_plan = current_user.user_reading_plans.find_by(plan_slug: @plan.slug)
    return redirect_to(reading_plans_path, alert: "Start the plan first.") unless user_plan

    user_plan.check_in!
    flash_message = user_plan.completed ? "🌟 Plan complete. Well done." : "Marked Day #{user_plan.current_day - 1} done. See you tomorrow."
    redirect_to reading_plan_path(@plan.slug), notice: flash_message
  end

  def leave
    current_user.user_reading_plans.where(plan_slug: @plan.slug).destroy_all
    redirect_to reading_plans_path, notice: "Left the plan."
  end

  private

  def set_plan
    @plan = ReadingPlan.find(params[:slug])
    redirect_to(reading_plans_path, alert: "Plan not found.") unless @plan
  end
end

# frozen_string_literal: true

# /walk — "Your walk" on a page of its own: the same card as the feed's left
# rail, for phones (linked from the feed strip and your profile).
class WalkController < ApplicationController
  before_action :authenticate_user!

  def show
    @user_reading_plan = current_user.user_reading_plans.where(completed: false).order(updated_at: :desc).first
  end
end

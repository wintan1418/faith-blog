# frozen_string_literal: true

# The getting-started list and the first-visit tour on the feed.
class OnboardingController < ApplicationController
  before_action :authenticate_user!

  # "Hide for now" on the list.
  def hide
    current_user.update_column(:onboarding_dismissed_at, Time.current)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove("onboarding_checklist") }
      format.html { redirect_to feed_path }
    end
  end

  # Settings → "Show the getting-started list again".
  def show_checklist
    current_user.update_column(:onboarding_dismissed_at, nil)
    redirect_to feed_path, notice: "Your getting-started list is back on the feed."
  end

  # The tour was finished or skipped: don't show it again.
  def finish_tour
    current_user.update_column(:tour_completed_at, Time.current) if current_user.tour_completed_at.nil?
    head :no_content
  end

  # Settings → "Take the tour again".
  def restart_tour
    current_user.update_column(:tour_completed_at, nil)
    redirect_to feed_path
  end
end

# frozen_string_literal: true

# Follow / unfollow a series. A signed-out visitor who taps Follow is sent to
# sign up and comes back to the series already following it (the follow
# waits in their session: see PendingSeriesFollow).
class SeriesFollowsController < ApplicationController
  before_action :authenticate_user!, only: :destroy
  before_action :set_series

  def create
    unless user_signed_in?
      PendingSeriesFollow.remember(session, @series)
      store_location_for(:user, series_path(@series))
      return redirect_to new_user_registration_path, notice: "Create your account and you'll be following “#{@series.title}”."
    end

    if @series.author?(current_user)
      redirect_to series_path(@series), alert: "That's your own series."
    else
      current_user.series_follows.find_or_create_by!(series: @series)
      redirect_back_or_to series_path(@series), notice: "Following “#{@series.title}”. You'll hear when a new part is up."
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_back_or_to series_path(@series)
  end

  def destroy
    current_user.series_follows.where(series: @series).delete_all
    redirect_back_or_to series_path(@series), notice: "You've stopped following “#{@series.title}”."
  end

  private

  def set_series
    @series = Series.friendly.find(params[:series_slug])
    raise ActiveRecord::RecordNotFound unless @series.readable_by?(current_user)
  end
end

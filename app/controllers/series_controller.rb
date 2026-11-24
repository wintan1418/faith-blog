# frozen_string_literal: true

# /series/:slug — every part of a writer's series in order. Open to
# signed-out readers (like a breath's page); the author also manages it here:
# rename, reorder, remove parts, or delete the series (the breaths stay).
class SeriesController < ApplicationController
  before_action :authenticate_user!, except: :show
  before_action :set_series
  before_action :require_author!, only: [ :update, :destroy ]

  def show
    raise ActiveRecord::RecordNotFound unless @series.readable_by?(current_user)

    @author = @series.author?(current_user)
    @parts = @series.parts_for(current_user)
  end

  def update
    if @series.update(series_params)
      redirect_to series_path(@series), notice: "Series saved."
    else
      redirect_to series_path(@series), alert: @series.errors.full_messages.to_sentence
    end
  end

  def destroy
    @series.destroy
    redirect_to user_path(current_user.username), notice: "Series removed. Its breaths are still yours, just no longer grouped."
  end

  private

  def set_series
    @series = Series.includes(user: :profile).friendly.find(params[:slug])
  end

  def require_author!
    return if @series.author?(current_user)

    redirect_to series_path(@series), alert: "Only the writer can change this series."
  end

  def series_params
    params.expect(series: [ :title, :description ])
  end
end

# frozen_string_literal: true

# The author reorders or removes the parts of their series. Removing a part
# only takes the breath out of the series; the breath itself stays.
class SeriesPartsController < ApplicationController
  # "Undo" on a series made automatically a moment ago takes the whole series
  # back; after this long it only takes the one breath out.
  UNDO_WINDOW = 1.hour

  before_action :authenticate_user!
  before_action :set_part

  def move
    @series.move!(@part, params[:direction].to_s == "up" ? -1 : 1)
    redirect_to series_path(@series, anchor: "part-#{@part.id}")
  end

  def destroy
    if params[:undo] == "created" && @series.created_at > UNDO_WINDOW.ago
      @series.destroy
      return redirect_to post_path(@part), notice: "Undone. “#{@series.title}” is no longer a series."
    end

    # Columns only: a breath's other validations shouldn't stand in the way.
    # The other parts keep their numbers.
    @part.update_columns(series_id: nil, series_position: nil)
    if params[:undo].present?
      redirect_to post_path(@part), notice: "Undone. This breath isn't part of “#{@series.title}”."
    else
      redirect_to series_path(@series), notice: "Taken out of the series. The breath itself is still there."
    end
  end

  private

  def set_part
    @series = current_user.series.friendly.find(params[:series_slug])
    @part = @series.posts.friendly.find(params[:id])
  end
end

# frozen_string_literal: true

# The author reorders or removes the parts of their series. Removing a part
# only takes the breath out of the series; the breath itself stays.
class SeriesPartsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_part

  def move
    @series.move!(@part, params[:direction].to_s == "up" ? -1 : 1)
    redirect_to series_path(@series, anchor: "part-#{@part.id}")
  end

  def destroy
    # Columns only: a breath's other validations shouldn't stand in the way.
    # The other parts keep their numbers.
    @part.update_columns(series_id: nil, series_position: nil)
    redirect_to series_path(@series), notice: "Taken out of the series. The breath itself is still there."
  end

  private

  def set_part
    @series = current_user.series.friendly.find(params[:series_slug])
    @part = @series.posts.friendly.find(params[:id])
  end
end

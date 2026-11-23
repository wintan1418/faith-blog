# frozen_string_literal: true

class Rooms::PostsController < ApplicationController
  before_action :set_room

  # There is no separate list page (it answered 406): the room page is the list.
  def index
    redirect_to room_path(@room), status: :moved_permanently
  end

  private

  def set_room
    @room = Room.friendly.find(params[:room_id])
    raise ActiveRecord::RecordNotFound unless @room.accessible_by?(current_user)
  end
end

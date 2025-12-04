# frozen_string_literal: true

class Rooms::PostsController < ApplicationController
  before_action :set_room

  def index
    @pagy, @posts = pagy(
      @room.posts.published.includes(:user, :tags).recent
    )
  end

  private

  def set_room
    @room = Room.friendly.find(params[:room_id])
  end
end


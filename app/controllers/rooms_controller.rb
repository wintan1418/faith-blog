# frozen_string_literal: true

class RoomsController < ApplicationController
  before_action :authenticate_user!, except: [:index, :show]
  before_action :set_room, only: [:show, :join, :leave]

  def index
    @rooms = Room.public_rooms.ordered
  end

  def show
    @pagy, @posts = pagy(
      @room.posts.published.includes(:user, :tags).recent
    )
    @is_member = current_user&.room_memberships&.exists?(room: @room)
  end

  def join
    membership = current_user.room_memberships.find_or_initialize_by(room: @room)
    
    if membership.new_record? && membership.save
      redirect_to @room, notice: "You've joined #{@room.name}!"
    else
      redirect_to @room, alert: "Unable to join room."
    end
  end

  def leave
    membership = current_user.room_memberships.find_by(room: @room)
    
    if membership&.destroy
      redirect_to @room, notice: "You've left #{@room.name}."
    else
      redirect_to @room, alert: "Unable to leave room."
    end
  end

  private

  def set_room
    @room = Room.friendly.find(params[:id])
  end
end


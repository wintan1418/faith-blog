# frozen_string_literal: true

class Admin::RoomsController < ApplicationController
  before_action :authenticate_admin!
  layout "admin"
  before_action :set_room, only: [:show, :edit, :update, :destroy]

  def index
    @rooms = Room.ordered
  end

  def show
  end

  def new
    @room = Room.new
  end

  def create
    @room = Room.new(room_params)
    if @room.save
      redirect_to admin_room_path(@room), notice: "Room created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @room.update(room_params)
      redirect_to admin_room_path(@room), notice: "Room updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @room.destroy
    redirect_to admin_rooms_path, notice: "Room deleted."
  end

  private

  def set_room
    @room = Room.friendly.find(params[:id])
  end

  def room_params
    params.require(:room).permit(:name, :description, :room_type, :icon, :color, :rules, :is_public, :position)
  end
end


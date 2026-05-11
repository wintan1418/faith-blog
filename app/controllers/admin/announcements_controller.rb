# frozen_string_literal: true

class Admin::AnnouncementsController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_announcement, only: [ :destroy ]
  layout "admin"

  def index
    @announcements = Announcement.order(created_at: :desc).limit(50)
  end

  def new
    @announcement = Announcement.new(kind: :release, kicker: "Just shipped")
  end

  def create
    @announcement = Announcement.new(announcement_params)
    if @announcement.save
      redirect_to admin_announcements_path, notice: "Announcement published."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @announcement.destroy
    redirect_to admin_announcements_path, notice: "Announcement removed."
  end

  private

  def set_announcement
    @announcement = Announcement.find(params[:id])
  end

  def announcement_params
    params.require(:announcement).permit(:kind, :title, :kicker, :body, :published_at, :expires_at)
  end
end

# frozen_string_literal: true

class Admin::BroadcastsController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_broadcast, only: [ :show, :edit, :update, :destroy, :send_now ]
  layout "admin"

  def index
    @broadcasts = Broadcast.includes(:sender).recent
    @eligible_user_count = Broadcast.eligible_user_count
  end

  def show
  end

  def new
    @broadcast = Broadcast.new_with_launch_template(sender: current_user)
    @eligible_user_count = Broadcast.eligible_user_count
  end

  def create
    @broadcast = Broadcast.new(broadcast_params)
    @broadcast.sender = current_user
    @broadcast.status = :draft

    if @broadcast.save
      redirect_to admin_broadcast_path(@broadcast), notice: "Draft saved. Review and send when ready."
    else
      @eligible_user_count = Broadcast.eligible_user_count
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    redirect_to admin_broadcast_path(@broadcast), alert: "Already sent — can't edit." and return if @broadcast.sent?
  end

  def update
    if @broadcast.sent?
      redirect_to admin_broadcast_path(@broadcast), alert: "Already sent — can't edit." and return
    end

    if @broadcast.update(broadcast_params)
      redirect_to admin_broadcast_path(@broadcast), notice: "Draft updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @broadcast.draft?
      @broadcast.destroy
      redirect_to admin_broadcasts_path, notice: "Draft deleted."
    else
      redirect_to admin_broadcast_path(@broadcast), alert: "Sent broadcasts are kept for record-keeping."
    end
  end

  def send_now
    if @broadcast.sent? || @broadcast.sending?
      redirect_to admin_broadcast_path(@broadcast), alert: "This broadcast has already been sent."
      return
    end

    BroadcastFanoutJob.perform_later(@broadcast)
    redirect_to admin_broadcast_path(@broadcast),
                notice: "Broadcast queued. It'll fan out to every eligible user within a few minutes."
  end

  private

  def set_broadcast
    @broadcast = Broadcast.find(params[:id])
  end

  def broadcast_params
    params.require(:broadcast).permit(:subject, :preheader, :body)
  end
end

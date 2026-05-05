# frozen_string_literal: true

class MessageBlocksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user
  before_action :ensure_not_self

  def create
    current_user.message_blocks.find_or_create_by!(blocked: @user)
    redirect_back fallback_location: conversations_path, notice: "#{@user.display_name} can no longer message you."
  end

  def destroy
    current_user.message_blocks.find_by(blocked: @user)&.destroy
    redirect_back fallback_location: conversations_path, notice: "#{@user.display_name} can message you again."
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end

  def ensure_not_self
    redirect_to conversations_path, alert: "You cannot block yourself." if @user == current_user
  end
end

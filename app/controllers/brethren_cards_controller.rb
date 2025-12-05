class BrethrenCardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user
  before_action :ensure_connected_or_owner

  def show
    @brethren_card = @user.brethren_card
  end

  private

  def set_user
    @user = User.find_by!(username: params[:username])
  end

  def ensure_connected_or_owner
    return if @user == current_user
    return if current_user.connected_with?(@user)

    redirect_to user_path(@user.username), 
                alert: "You need to connect with #{@user.display_name} first to view their Brethren Card."
  end
end


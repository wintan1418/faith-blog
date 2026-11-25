class BrethrenCardsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_user
  before_action :ensure_allowed

  def show
    @brethren_card = @user.brethren_card
    @owner = @user == current_user
    # Church, occupation and about are for connections; someone who isn't
    # connected only gets here because the member shared contact details with
    # them (or made them public), so they see just those.
    @full_card = @owner || @connected || current_user.contact_privacy_exempt?
    @contact = @brethren_card ? @brethren_card.visible_contact_for(current_user, connected: @connected) : {}
  end

  private

  def set_user
    @user = User.active.find_by!(username: params[:username])
  end

  def ensure_allowed
    return if @user == current_user || current_user.contact_privacy_exempt?
    return deny! if MessageBlock.between?(current_user, @user)

    @connected = current_user.connected_with?(@user)
    return if @connected

    card = @user.brethren_card
    return if card && card.visible_contact_for(current_user, connected: false).any?

    deny!
  end

  def deny!
    redirect_to user_path(@user.username),
                alert: "You need to connect with #{@user.display_name} first to view their Brethren Card."
  end
end

class ConnectionRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_connection_request, only: [:accept, :decline]

  def index
    @pending_requests = current_user.received_connection_requests.pending.includes(sender: :brethren_card)
    @sent_requests = current_user.sent_connection_requests.includes(receiver: :brethren_card)
  end

  def connections
    @connections = current_user.connections
  end

  def create
    receiver = User.find(params[:receiver_id])
    
    # Check if current user's brethren card is complete
    unless current_user.brethren_card&.complete?
      redirect_back fallback_location: settings_brethren_card_path,
                    alert: "Please complete your Brethren Card before sending connection requests."
      return
    end

    # Check if connection request already exists
    existing = ConnectionRequest.between(current_user, receiver)
    if existing
      if existing.accepted?
        redirect_back fallback_location: user_path(receiver.username),
                      notice: "You're already connected with #{receiver.display_name}!"
      elsif existing.pending?
        redirect_back fallback_location: user_path(receiver.username),
                      notice: "A connection request is already pending."
      else
        # If declined, allow to request again
        existing.update(status: :pending, sender: current_user, receiver: receiver)
        redirect_back fallback_location: user_path(receiver.username),
                      notice: "Connection request sent to #{receiver.display_name}!"
      end
      return
    end

    @connection_request = ConnectionRequest.new(
      sender: current_user,
      receiver: receiver,
      message: params[:message]
    )

    if @connection_request.save
      redirect_back fallback_location: user_path(receiver.username),
                    notice: "Connection request sent to #{receiver.display_name}! They'll receive your Brethren Card once they accept."
    else
      redirect_back fallback_location: user_path(receiver.username),
                    alert: @connection_request.errors.full_messages.join(", ")
    end
  end

  def accept
    if @connection_request.update(status: :accepted)
      redirect_back fallback_location: connection_requests_path,
                    notice: "You're now connected with #{@connection_request.sender.display_name}! You can now view each other's Brethren Cards."
    else
      redirect_back fallback_location: connection_requests_path,
                    alert: "Could not accept request."
    end
  end

  def decline
    if @connection_request.update(status: :declined)
      redirect_back fallback_location: connection_requests_path,
                    notice: "Request declined."
    else
      redirect_back fallback_location: connection_requests_path,
                    alert: "Could not decline request."
    end
  end

  private

  def set_connection_request
    @connection_request = ConnectionRequest.find(params[:id])
    
    unless @connection_request.receiver == current_user
      redirect_back fallback_location: connection_requests_path,
                    alert: "You can only respond to requests sent to you."
    end
  end
end


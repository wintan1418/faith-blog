class ConnectionRequestsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_connection_request, only: [ :accept, :decline ]

  def index
    @pending_requests = current_user.received_connection_requests.pending.includes(sender: :brethren_card)
    @sent_requests = current_user.sent_connection_requests.includes(receiver: :brethren_card)
  end

  def connections
    @connections = current_user.connections
  end

  def create
    @receiver = User.find(params[:receiver_id])

    # Check if current user's brethren card is complete
    unless current_user.brethren_card&.complete?
      respond_to do |format|
        format.html do
          redirect_back fallback_location: edit_settings_brethren_card_path,
                        alert: "Please complete your Brethren Card before sending connection requests."
        end
        format.turbo_stream do
          flash.now[:alert] = "Please complete your Brethren Card before sending connection requests."
          render :create, status: :unprocessable_entity
        end
      end
      return
    end

    # Check if connection request already exists
    existing = ConnectionRequest.between(current_user, @receiver)
    if existing
      @connection_request = existing
      if existing.accepted?
        respond_to do |format|
          format.html do
            redirect_back fallback_location: user_path(@receiver.username),
                          notice: "You're already connected with #{@receiver.display_name}!"
          end
          format.turbo_stream do
            flash.now[:notice] = "You're already connected with #{@receiver.display_name}!"
            render :create
          end
        end
      elsif existing.pending?
        respond_to do |format|
          format.html do
            redirect_back fallback_location: user_path(@receiver.username),
                          notice: "A connection request is already pending."
          end
          format.turbo_stream do
            flash.now[:notice] = "A connection request is already pending."
            render :create
          end
        end
      else
        # If declined, allow to request again
        existing.update(status: :pending, sender: current_user, receiver: @receiver)
        respond_to do |format|
          format.html do
            redirect_back fallback_location: user_path(@receiver.username),
                          notice: "Connection request sent to #{@receiver.display_name}!"
          end
          format.turbo_stream do
            flash.now[:notice] = "Connection request sent to #{@receiver.display_name}!"
            render :create
          end
        end
      end
      return
    end

    @connection_request = ConnectionRequest.new(
      sender: current_user,
      receiver: @receiver,
      message: params[:message]
    )

    if @connection_request.save
      respond_to do |format|
        format.html do
          redirect_back fallback_location: user_path(@receiver.username),
                        notice: "Connection request sent to #{@receiver.display_name}! They'll receive your Brethren Card once they accept."
        end
        format.turbo_stream do
          flash.now[:notice] = "Connection request sent to #{@receiver.display_name}! They'll receive your Brethren Card once they accept."
        end
      end
    else
      respond_to do |format|
        format.html do
          redirect_back fallback_location: user_path(@receiver.username),
                        alert: @connection_request.errors.full_messages.join(", ")
        end
        format.turbo_stream do
          flash.now[:alert] = @connection_request.errors.full_messages.join(", ")
          render :create, status: :unprocessable_entity
        end
      end
    end
  end

  def accept
    if @connection_request.update(status: :accepted)
      respond_to do |format|
        format.html do
          redirect_back fallback_location: connection_requests_path,
                        notice: "You're now connected with #{@connection_request.sender.display_name}! You can now view each other's Brethren Cards."
        end
        format.turbo_stream do
          @receiver = @connection_request.sender
          set_pending_requests
          flash.now[:notice] = "You're now connected with #{@connection_request.sender.display_name}! You can now view each other's Brethren Cards."
        end
      end
    else
      respond_to do |format|
        format.html { redirect_back fallback_location: connection_requests_path, alert: "Could not accept request." }
        format.turbo_stream do
          @receiver = @connection_request.sender
          set_pending_requests
          flash.now[:alert] = "Could not accept request."
          render :accept, status: :unprocessable_entity
        end
      end
    end
  end

  def decline
    if @connection_request.update(status: :declined)
      respond_to do |format|
        format.html { redirect_back fallback_location: connection_requests_path, notice: "Request declined." }
        format.turbo_stream do
          @receiver = @connection_request.sender
          set_pending_requests
          flash.now[:notice] = "Request declined."
        end
      end
    else
      respond_to do |format|
        format.html { redirect_back fallback_location: connection_requests_path, alert: "Could not decline request." }
        format.turbo_stream do
          @receiver = @connection_request.sender
          set_pending_requests
          flash.now[:alert] = "Could not decline request."
          render :decline, status: :unprocessable_entity
        end
      end
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

  def set_pending_requests
    @pending_requests = current_user.received_connection_requests.pending.includes(sender: :brethren_card)
  end
end

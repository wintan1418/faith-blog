# frozen_string_literal: true

# "Breathers around you" (/around): members near you who chose to be found.
# See BreathersAround for the privacy rules.
class AroundController < ApplicationController
  before_action :authenticate_user!
  before_action :load_profile
  member_rate_limit to: 30, within: 1.hour, only: :hello, name: "around-hello",
                    message: "You've said hello to a lot of people this hour. Please try again later."
  # Strangers get a connection request instead (ConnectionRequestsController),
  # capped at ConnectionRequest::AROUND_HELLOS_PER_DAY.

  def show
    @around = BreathersAround.new(current_user)
    return render(:too_young) unless @around.allowed?
    return redirect_to(city_around_path) unless @profile.city
    return render(:too_new) unless @around.account_old_enough?

    # Seeing requires showing: until they're findable themselves, the opt-in screen.
    unless @around.showing?
      @count_near = @around.count_near
      return render(:opt_in)
    end

    @filters = filters
    @sections = @around.sections(@filters)
    @dots = @around.map_dots(@filters)
    @industries = @around.top_industries
    @in_rooms = RoomMembership.exists?(user_id: current_user.id)
    people = @sections.flat_map(&:people)
    @shared_rooms = @around.shared_rooms(people.map { |p| p.user.id })
    @connections = ConnectionRequest.where(sender_id: current_user.id, receiver_id: people.map { |p| p.user.id })
                                    .or(ConnectionRequest.where(receiver_id: current_user.id, sender_id: people.map { |p| p.user.id }))
                                    .index_by { |c| c.sender_id == current_user.id ? c.receiver_id : c.sender_id }
  end

  # Your city, who can see it, and the on/off switch.
  def city; end

  def update
    if @profile.update(around_params)
      redirect_to around_path, notice: update_notice
    else
      redirect_to city_around_path, alert: @profile.errors.full_messages.to_sentence
    end
  end

  # "Say hello" to a connection: the note goes straight into your conversation.
  # (Others get a connection request with the note, through ConnectionRequestsController.)
  def hello
    recipient = User.active.find(params[:recipient_id])
    unless current_user.connected_with?(recipient) && !MessageBlock.between?(current_user, recipient)
      return redirect_to(around_path, alert: "You can only message your connections.")
    end

    conversation = Conversation.find_or_create_between!(current_user, recipient)
    message = conversation.messages.build(sender: current_user, body: params[:body].to_s.strip.first(1000))
    if message.save
      redirect_to conversation_path(conversation)
    else
      redirect_to around_path, alert: message.errors.full_messages.to_sentence
    end
  end

  private

  def load_profile
    @profile = current_user.profile || current_user.create_profile!
  end

  def around_params
    optional_params(:profile).permit(:show_in_nearby, :city_visibility, :city_id, :location).tap do |p|
      p.delete(:city_visibility) unless Profile.city_visibilities.key?(p[:city_visibility].to_s)
    end
  end

  def update_notice
    return "Saved." unless @profile.saved_change_to_show_in_nearby?

    return "You're now visible to breathers near #{@profile.city&.name || 'you'}." if @profile.show_in_nearby?

    "You're hidden from Breathers around you. Turn Show me back on any time to see who's around."
  end

  # One filter at a time (the pills): mentoring, an industry, or my rooms.
  def filters
    {
      mentoring: params[:filter] == "mentoring",
      industry: Profile::INDUSTRIES.include?(params[:industry]) ? params[:industry] : nil,
      my_rooms: params[:filter] == "rooms"
    }
  end
end

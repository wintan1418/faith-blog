# frozen_string_literal: true

# The buttons on Office cards. Each acts on one card (an OfficeMessage in one
# of the current admin's conversations) and re-renders it in place.
class Admin::Office::CardsController < Admin::Office::BaseController
  before_action :set_message

  def update_breath
    return render_card unless breath_draft?

    room = Room.public_rooms.find_by(id: params[:room_id])
    @message.update_card!(
      "title" => params[:title].to_s.strip.truncate(200),
      "body" => params[:body].to_s.strip,
      "room_id" => room&.id, "room_name" => room&.name,
      "prayer" => params[:prayer] == "1",
      "editing" => false, "error" => nil
    )
    render_card
  end

  # "Post now", or "Schedule" when a time comes with it.
  def post_breath
    return render_card unless breath_draft?

    schedule_at = Ai::Office::BreathPublisher.parse_time(params[:schedule_at])
    if params[:schedule_at].present? && (schedule_at.nil? || schedule_at <= Time.current)
      @message.update_card!("error" => "Pick a time in the future to schedule it.")
      return render_card
    end

    result = Ai::Office::BreathPublisher.new(card: @message.card_data, admin: current_user, schedule_at: schedule_at).call
    if result.ok?
      post = result.post
      @message.update_card!("status" => post.scheduled? ? "scheduled" : "posted", "post_id" => post.id,
                            "post_slug" => post.slug, "scheduled_for" => post.scheduled_for&.iso8601, "error" => nil)
    else
      @message.update_card!("error" => result.errors.to_sentence)
    end
    render_card
  end

  # From a flyer card: start a breath card with the image attached.
  def use_in_breath
    return render_card unless @message.card_kind == "flyer" && @message.image.attached?

    card = @message.conversation.messages.create!(
      role: :card,
      content: "The founder started a breath using the flyer (#{@message.card_data['brief'].to_s.truncate(120)}).",
      payload: { "card" => { "kind" => "breath", "status" => "draft", "title" => "", "body" => "", "prayer" => false,
                             "image_message_id" => @message.id, "editing" => true,
                             "author" => Ai::Office::BreathPublisher.author_for(current_user).username } }
    )
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.append("office_messages", partial: "admin/office/messages/message", locals: { message: card }) }
      format.html { redirect_to admin_office_conversation_path(@message.conversation) }
    end
  end

  def publish_announcement
    return render_card unless @message.card_kind == "announcement" && @message.card_data["status"] == "draft"

    data = @message.card_data
    announcement = Announcement.new(user: current_user, kind: data["announcement_kind"].presence_in(%w[release custom]) || "release",
                                    title: data["title"], kicker: data["kicker"].presence, body: data["body"])
    if announcement.save
      @message.update_card!("status" => "published", "announcement_id" => announcement.id, "error" => nil)
    else
      @message.update_card!("error" => announcement.errors.full_messages.to_sentence)
    end
    render_card
  end

  private

  def set_message
    @message = OfficeMessage.joins(:conversation)
                            .where(office_conversations: { user_id: current_user.id })
                            .find(params[:id])
  end

  def breath_draft?
    @message.card_kind == "breath" && @message.card_data["status"] == "draft"
  end

  def render_card
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace(@message, partial: "admin/office/messages/message", locals: { message: @message }) }
      format.html { redirect_to admin_office_conversation_path(@message.conversation) }
    end
  end
end

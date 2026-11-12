# frozen_string_literal: true

# The buttons on Office cards. Each acts on one card (an OfficeMessage in one
# of the current admin's conversations) and re-renders it in place.
class Admin::Office::CardsController < Admin::Office::BaseController
  UPLOAD_TYPES = AttachmentValidatable::IMAGE_CONTENT_TYPES
  UPLOAD_MAX_BYTES = Post::IMAGE_MAX_BYTES

  before_action :set_message
  before_action :require_breath, only: %i[image_picker attach_image remove_image]

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
      @message.update_card!(Ai::Office::BreathPublisher.card_attrs_for(result.post))
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
      content: "The founder started a new breath card with flyer #{@message.id} (#{@message.card_data['brief'].to_s.truncate(120)}).",
      payload: { "card" => { "kind" => "breath", "status" => "draft", "title" => "", "body" => "", "prayer" => false,
                             "image_message_id" => @message.id, "editing" => true,
                             "author" => Ai::Office::BreathPublisher.author_for(current_user).username } }
    )
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.append("office_messages", partial: "admin/office/messages/message", locals: { message: card }) }
      format.html { redirect_to admin_office_conversation_path(@message.conversation) }
    end
  end

  # Breath card → "Add flyer" / "Change image": the images in this
  # conversation to choose from, plus an upload. Loaded into a turbo frame
  # each time the picker opens, so new flyers show up.
  def image_picker
    images = @message.conversation.messages.joins(:image_attachment).with_attached_image.reorder(id: :desc).limit(24)
    render partial: "admin/office/cards/image_picker", locals: { message: @message, images: images }
  end

  # Breath card: show an image from the conversation (source_id) or an uploaded one (image).
  def attach_image
    source_id = params[:source_id].presence
    if source_id.nil?
      error = upload_error(params[:image])
      if error
        @message.update_card!("error" => error)
        return render_card
      end
      @message.image.attach(params[:image])
      source_id = @message.id
    end
    Ai::Office::BreathCard.new(@message, admin: current_user).update("image_message_id" => source_id)
    render_card
  end

  def remove_image
    Ai::Office::BreathCard.new(@message, admin: current_user).update("image_message_id" => nil)
    render_card
  end

  # Flyer card → "Add to a breath": the breath cards in this conversation, newest first.
  def breath_picker
    breaths = @message.conversation.messages.where("payload -> 'card' ->> 'kind' = 'breath'").reorder(id: :desc).limit(30)
    render partial: "admin/office/cards/breath_picker", locals: { message: @message, breaths: breaths }
  end

  def add_to_breath
    breath = @message.conversation.messages.find(params[:breath_id])
    return render_card unless @message.image.attached? && Ai::Office::BreathCard.breath?(breath)

    Ai::Office::BreathCard.new(breath, admin: current_user).update("image_message_id" => @message.id)
    @message = breath
    render_card
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

  def require_breath
    render_card unless Ai::Office::BreathCard.breath?(@message)
  end

  def upload_error(file)
    return "Choose an image to upload." unless file.respond_to?(:content_type) && file.respond_to?(:size)
    return "That file isn't an image. Use a JPEG, PNG, WebP or GIF." unless UPLOAD_TYPES.include?(file.content_type)

    "That image is too large (max #{UPLOAD_MAX_BYTES / 1.megabyte}MB)." if file.size > UPLOAD_MAX_BYTES
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

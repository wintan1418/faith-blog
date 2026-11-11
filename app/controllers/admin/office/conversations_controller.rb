# frozen_string_literal: true

class Admin::Office::ConversationsController < Admin::Office::BaseController
  before_action :set_conversation, only: [ :show, :update, :destroy, :retry, :refresh ]

  # /admin/office: a fresh composer; the first message starts a thread.
  def index
    @conversation = nil
    render :show
  end

  def show
    @messages = @conversation.messages.with_attached_image
  end

  # Starts a thread, optionally with its first message (the empty-state composer).
  def create
    @conversation = conversations.create!
    content = params.dig(:message, :content).to_s.strip
    if content.present?
      @conversation.messages.create!(role: :user, content: content)
      @conversation.title_from!(content)
      @conversation.thinking!(true)
      OfficeReplyJob.perform_later(@conversation.id)
    end
    redirect_to admin_office_conversation_path(@conversation)
  end

  def update
    @conversation.update(title: params.dig(:conversation, :title).to_s.strip.presence || OfficeConversation::DEFAULT_TITLE)
    redirect_to admin_office_conversation_path(@conversation)
  end

  def destroy
    @conversation.destroy
    redirect_to admin_office_path, notice: "Conversation deleted."
  end

  # "Import notes": paste a transcript from elsewhere; it becomes the first
  # message of a new thread, read as context on every reply.
  def import
    notes = params[:notes].to_s.strip
    if notes.blank?
      redirect_to admin_office_path, alert: "Paste some notes to import." and return
    end

    @conversation = conversations.create!(title: params[:title].to_s.strip.presence&.truncate(120) || "Imported notes")
    @conversation.messages.create!(role: :user, content: notes.truncate(150_000), payload: { "imported" => true })
    @conversation.touch_last_message!
    redirect_to admin_office_conversation_path(@conversation), notice: "Notes imported. Ask away."
  end

  def retry
    unless @conversation.busy?
      @conversation.thinking!(true)
      OfficeReplyJob.perform_later(@conversation.id)
    end
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("office_status", partial: "admin/office/conversations/status", locals: { conversation: @conversation }) }
      format.html { redirect_to admin_office_conversation_path(@conversation) }
    end
  end

  # Polled while a reply is being written, in case the live connection drops
  # (flaky mobile data, the Android app in the background).
  def refresh
    @messages = @conversation.messages.with_attached_image
    render turbo_stream: [
      turbo_stream.update("office_messages", partial: "admin/office/messages/message", collection: @messages, as: :message),
      turbo_stream.replace("office_status", partial: "admin/office/conversations/status", locals: { conversation: @conversation })
    ]
  end

  private

  def set_conversation
    @conversation = conversations.find(params[:id])
  end
end

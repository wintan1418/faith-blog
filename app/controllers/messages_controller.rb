# frozen_string_literal: true

class MessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_conversation
  before_action :set_message,    only: [ :update, :destroy ]
  before_action :authorize_own!, only: [ :update, :destroy ]

  def create
    @message = @conversation.messages.build(message_params)
    @message.sender = current_user

    if @message.save
      @conversation.mark_read_for!(current_user)
      @messages = @conversation.messages.visible.includes(sender: { profile: { avatar_attachment: :blob } }).oldest_first
      respond_to do |format|
        format.html { redirect_to conversation_path(@conversation) }
        format.turbo_stream
      end
    else
      @conversations = current_user.conversations
                                   .joins(:conversation_participants)
                                   .where(conversation_participants: { user_id: current_user.id, archived_at: nil })
                                   .includes(conversation_participants: { user: { profile: { avatar_attachment: :blob } } })
                                   .recent
      @messages = @conversation.messages.visible.includes(sender: { profile: { avatar_attachment: :blob } }).oldest_first
      respond_to do |format|
        format.html { render "conversations/show", status: :unprocessable_entity }
        format.turbo_stream { render "conversations/show", status: :unprocessable_entity }
      end
    end
  end

  def update
    if @message.update(message_params.merge(edited_at: Time.current))
      respond_to do |format|
        format.html { redirect_to conversation_path(@conversation) }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            ActionView::RecordIdentifier.dom_id(@message),
            partial: "conversations/message",
            locals: { message: @message, viewer_id: current_user.id }
          )
        }
      end
    else
      redirect_to conversation_path(@conversation), alert: "Could not update message."
    end
  end

  def destroy
    @message.update(deleted_at: Time.current, body: "[deleted]")
    respond_to do |format|
      format.html { redirect_to conversation_path(@conversation) }
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace(
          ActionView::RecordIdentifier.dom_id(@message),
          partial: "conversations/message",
          locals: { message: @message, viewer_id: current_user.id }
        )
      }
    end
  end

  private

  def set_conversation
    @conversation = current_user.conversations.find(params[:conversation_id])
  end

  def set_message
    @message = @conversation.messages.find(params[:id])
  end

  def authorize_own!
    return if @message.sender_id == current_user.id

    redirect_to conversation_path(@conversation), alert: "Only the author can edit or delete this message."
  end

  def message_params
    params.require(:message).permit(:body, :voice_note, images: [])
  end
end

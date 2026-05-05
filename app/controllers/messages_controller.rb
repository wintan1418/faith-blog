# frozen_string_literal: true

class MessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_conversation

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

  private

  def set_conversation
    @conversation = current_user.conversations.find(params[:conversation_id])
  end

  def message_params
    params.require(:message).permit(:body)
  end
end

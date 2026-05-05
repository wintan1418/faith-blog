# frozen_string_literal: true

class ConversationTypingChannel < ApplicationCable::Channel
  def subscribed
    @conversation = current_user.conversations.find(params[:conversation_id])
    stream_for @conversation
  rescue ActiveRecord::RecordNotFound
    reject
  end

  def typing(data)
    ConversationTypingChannel.broadcast_to(
      @conversation,
      user_id: current_user.id,
      username: current_user.display_name,
      typing: ActiveModel::Type::Boolean.new.cast(data["typing"])
    )
  end
end

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
  rescue StandardError => e
    # Typing pings fire on every keystroke — if the cable adapter throws
    # (solid_cable has been flaky with upsert on certain schemas), don't
    # spam exception backtraces into the log. The user-visible cost of a
    # missed typing indicator is zero.
    Rails.logger.warn("[ConversationTypingChannel] #{e.class}: #{e.message}")
  end
end

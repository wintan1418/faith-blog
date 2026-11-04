# frozen_string_literal: true

class MessagesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_conversation
  before_action :set_message,    only: [ :update, :destroy, :pick_forward, :forward ]
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
        # Keep the chat on screen: just show why, with what they typed still in the box.
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace("new_message", partial: "conversations/composer",
                                                                   locals: { conversation: @conversation, message: @message }),
                 status: :unprocessable_entity
        end
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

  # Choose which chats to forward a message to.
  def pick_forward
    return redirect_to(conversation_path(@conversation), alert: "This message can't be forwarded.") unless @message.forwardable?

    @targets = forward_targets.to_a
  end

  def forward
    return redirect_to(conversation_path(@conversation), alert: "This message can't be forwarded.") unless @message.forwardable?

    ids = Array(params[:conversation_ids]).map(&:to_i).uniq.first(Message::FORWARD_LIMIT)
    sent = forward_targets.where(id: ids).map { |target| @message.forward_to(target, by: current_user) }
    delivered = sent.select(&:persisted?)

    if delivered.size == 1
      redirect_to conversation_path(delivered.first.conversation), notice: "Forwarded."
    elsif delivered.any?
      redirect_to conversation_path(@conversation), notice: "Forwarded to #{delivered.size} chats."
    else
      reason = sent.flat_map { |m| m.errors.full_messages }.first || "Choose a chat to forward to."
      redirect_to forward_conversation_message_path(@conversation, @message), alert: reason
    end
  end

  private

  # The member's own active chats, newest first.
  def forward_targets
    archived = ConversationParticipant.where(user: current_user).where.not(archived_at: nil).select(:conversation_id)
    current_user.conversations
                .where.not(id: archived)
                .preload(conversation_participants: { user: { profile: { avatar_attachment: :blob } } })
                .recent.limit(40)
  end

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
    params.require(:message).permit(:body, :voice_note, :scripture_ref, :reply_to_id, images: [], documents: [])
  end
end

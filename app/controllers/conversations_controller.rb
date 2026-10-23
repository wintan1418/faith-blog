# frozen_string_literal: true

class ConversationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_conversation, only: [ :show, :archive, :mark_read ]

  def index
    @filter = params[:filter] == "unread" ? "unread" : "all"
    @conversations = conversation_scope.reject { |c| c.last_message_at.nil? }
    @unread_total = @conversations.count { |c| c.unread_count_for(current_user).positive? }
    @conversations = @conversations.select { |c| c.unread_count_for(current_user).positive? } if @filter == "unread"
    # Computers show the newest conversation beside the list; phones show the list only.
    @conversation = @conversations.first
    load_thread if @conversation
  end

  # "New message": pick one of your connections.
  def new
    @connections = current_user.connections.uniq.sort_by { |u| u.display_name.downcase }
  end

  def show
    load_sidebar
    load_thread
    @conversation.mark_read_for!(current_user)
  end

  def create
    @recipient = User.find(params[:recipient_id])
    unless current_user.connected_with?(@recipient)
      redirect_back fallback_location: user_path(@recipient.username), alert: "You can only message accepted connections."
      return
    end
    if MessageBlock.between?(current_user, @recipient)
      redirect_back fallback_location: user_path(@recipient.username), alert: "Messaging is blocked between you and #{@recipient.display_name}."
      return
    end

    @conversation = Conversation.find_or_create_between!(current_user, @recipient)
    redirect_to conversation_path(@conversation)
  end

  def archive
    @conversation.participant_for(current_user)&.update!(archived_at: Time.current)
    redirect_to conversations_path, notice: "Conversation archived."
  end

  def search
    @query = params[:q].to_s.strip
    if @query.length >= 2
      conversation_ids = current_user.conversations.pluck(:id)
      messages = Message.visible
                        .where(conversation_id: conversation_ids)
                        .where("body ILIKE ?", "%#{@query}%")
                        .includes(:sender, conversation: :conversation_participants)
                        .order(created_at: :desc)
      @pagy, @results = pagy(messages, items: 25)
    else
      @pagy = nil
      @results = []
    end
  end

  def mark_read
    @conversation.mark_read_for!(current_user)
    redirect_to conversation_path(@conversation)
  end

  private

  def set_conversation
    @conversation = current_user.conversations.find(params[:id])
  end

  # Chats opened but never written in stay out of the list (except the one you're in).
  def load_sidebar
    @conversations = conversation_scope.reject { |c| c.last_message_at.nil? && c != @conversation }
  end

  def load_thread
    @messages = @conversation.messages.visible.includes(sender: { profile: { avatar_attachment: :blob } }).oldest_first
    @message = Message.new
  end

  def conversation_scope
    # Use a subquery instead of joins + DISTINCT. Postgres rejects
    # SELECT DISTINCT when ORDER BY references a column outside the
    # select list (we order by COALESCE(last_message_at, created_at)).
    active_ids = ConversationParticipant.where(
      user_id: current_user.id, archived_at: nil
    ).select(:conversation_id)

    Conversation.where(id: active_ids)
                .includes(conversation_participants: { user: { profile: { avatar_attachment: :blob } } })
                .recent
  end
end

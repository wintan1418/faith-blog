# frozen_string_literal: true

class ConversationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_conversation, only: [ :show, :archive, :mark_read, :earlier ]

  def index
    @filter = params[:filter] == "unread" ? "unread" : "all"
    @conversations = conversation_scope.reject { |c| c.last_message_at.nil? }
    load_list_meta
    @unread_total = @conversations.count { |c| @unread_by_conversation[c.id].to_i.positive? }
    @conversations = @conversations.select { |c| @unread_by_conversation[c.id].to_i.positive? } if @filter == "unread"
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
    clear_message_notifications
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
    # A ready-to-send greeting (e.g. "Happy birthday!") can ride along into the composer.
    redirect_to conversation_path(@conversation, draft: params[:draft].presence&.first(500))
  end

  # "Load earlier messages": the previous page, inserted above what's on screen.
  def earlier
    before = @conversation.messages.find(params[:before])
    @older = thread_scope.where(created_at: ...before.created_at).order(created_at: :desc).limit(THREAD_PAGE).to_a.reverse
    @has_earlier = @older.any? && thread_scope.where(created_at: ...@older.first.created_at).exists?
    @seam = thread_scope.find(before.id)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to conversation_path(@conversation) }
    end
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
    clear_message_notifications
    redirect_to conversation_path(@conversation)
  end

  private

  # Reading a conversation clears its chat notifications.
  def clear_message_notifications
    current_user.notifications.unread.direct_message
                .where(notifiable_type: "Message", notifiable_id: @conversation.messages.select(:id))
                .update_all(read_at: Time.current)
  end

  def set_conversation
    @conversation = current_user.conversations.find(params[:id])
  end

  # Chats opened but never written in stay out of the list (except the one you're in).
  def load_sidebar
    @conversations = conversation_scope.reject { |c| c.last_message_at.nil? && c != @conversation }
    load_list_meta
  end

  # Speed: open with the latest messages; "Load earlier messages" fetches the rest in pages.
  THREAD_PAGE = 50

  def load_thread
    newest = thread_scope.order(created_at: :desc).limit(THREAD_PAGE).to_a
    @messages = newest.reverse
    @has_earlier = @messages.any? && thread_scope.where(created_at: ...@messages.first.created_at).exists?
    @message = Message.new
  end

  def thread_scope
    @conversation.messages.visible.includes({ sender: { profile: { avatar_attachment: :blob } } }, { likes: :user })
  end

  # Latest message and unread count for every row in one go (was 3 queries per row).
  def load_list_meta
    ids = @conversations.map(&:id)
    @latest_by_conversation = Message.visible.where(conversation_id: ids)
                                     .select("DISTINCT ON (messages.conversation_id) messages.*")
                                     .order("messages.conversation_id, messages.created_at DESC")
                                     .index_by(&:conversation_id)
    @unread_by_conversation = Message.visible.where(conversation_id: ids).where.not(sender_id: current_user.id)
                                     .joins("INNER JOIN conversation_participants cp ON cp.conversation_id = messages.conversation_id")
                                     .where(cp: { user_id: current_user.id })
                                     .where("cp.last_read_at IS NULL OR messages.created_at > cp.last_read_at")
                                     .group("messages.conversation_id").count
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

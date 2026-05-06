# frozen_string_literal: true

class LikesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_likeable

  def create
    @like = current_user.likes.find_or_initialize_by(likeable: @likeable)
    new_reaction = @like.new_record?

    emoji = params[:reaction_emoji].to_s.strip
    if emoji.present?
      @like.reaction_emoji = emoji
      @like.reaction_type  = Like.enum_for_emoji(emoji)
    else
      enum = params[:reaction_type] || :amen
      @like.reaction_type  = enum
      @like.reaction_emoji = Like.reaction_emoji(enum)
    end

    if @like.save
      @likeable.reload
      create_notification if new_reaction
      broadcast_message_reaction(@likeable) if @likeable.is_a?(Message)
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path }
        format.turbo_stream
      end
    else
      redirect_back fallback_location: root_path, alert: "Unable to add reaction."
    end
  end

  def destroy
    @like = current_user.likes.find_by(likeable: @likeable)

    if @like&.destroy
      @likeable.reload
      broadcast_message_reaction(@likeable) if @likeable.is_a?(Message)
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path }
        format.turbo_stream
      end
    else
      redirect_back fallback_location: root_path, alert: "Unable to remove reaction."
    end
  end

  private

  def set_likeable
    @likeable_type = params[:likeable_type].to_s.classify
    @likeable_id = params[:likeable_id]

    likeable_class = { "Post" => Post, "Comment" => Comment, "Message" => Message }[@likeable_type]
    raise ActiveRecord::RecordNotFound unless likeable_class

    @likeable = likeable_class.find(@likeable_id)
  rescue ActiveRecord::RecordNotFound
    redirect_back fallback_location: root_path, alert: "Invalid content."
  end

  def create_notification
    return if @likeable.is_a?(Message)
    return if @likeable.user == current_user

    notification_type = @likeable.is_a?(Post) ? :post_liked : :comment_liked

    Notification.create(
      user: @likeable.user,
      actor: current_user,
      notifiable: @like,
      notification_type: notification_type
    )
  end

  # Push the updated message bubble to every participant's existing
  # cable subscription on [conversation, user_id, :messages] so reactions
  # appear live for both sides without a page refresh.
  def broadcast_message_reaction(message)
    message.conversation.conversation_participants.find_each do |participant|
      Turbo::StreamsChannel.broadcast_replace_later_to(
        [ message.conversation, participant.user_id, :messages ],
        target: ActionView::RecordIdentifier.dom_id(message),
        partial: "conversations/message",
        locals: { message: message, viewer_id: participant.user_id }
      )
    end
  end
end

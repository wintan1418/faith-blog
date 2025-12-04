# frozen_string_literal: true

class CommentsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_post
  before_action :set_comment, only: [:update, :destroy, :reply]
  before_action :authorize_comment!, only: [:update, :destroy]

  def create
    @comment = @post.comments.build(comment_params)
    @comment.user = current_user

    if @comment.save
      create_notification
      respond_to do |format|
        format.html { redirect_to @post, notice: "Comment added!" }
        format.turbo_stream
      end
    else
      respond_to do |format|
        format.html { redirect_to @post, alert: "Unable to add comment." }
        format.turbo_stream { render turbo_stream: turbo_stream.replace("comment_form", partial: "comments/form", locals: { post: @post, comment: @comment }) }
      end
    end
  end

  def reply
    @reply = @post.comments.build(comment_params)
    @reply.user = current_user
    @reply.parent_comment = @comment

    if @reply.save
      create_reply_notification
      respond_to do |format|
        format.html { redirect_to @post, notice: "Reply added!" }
        format.turbo_stream
      end
    else
      respond_to do |format|
        format.html { redirect_to @post, alert: "Unable to add reply." }
        format.turbo_stream
      end
    end
  end

  def update
    if @comment.update(comment_params)
      @comment.mark_as_edited!
      respond_to do |format|
        format.html { redirect_to @post, notice: "Comment updated!" }
        format.turbo_stream
      end
    else
      respond_to do |format|
        format.html { redirect_to @post, alert: "Unable to update comment." }
        format.turbo_stream
      end
    end
  end

  def destroy
    @comment.soft_delete!
    respond_to do |format|
      format.html { redirect_to @post, notice: "Comment deleted." }
      format.turbo_stream
    end
  end

  private

  def set_post
    @post = Post.friendly.find(params[:post_id])
  end

  def set_comment
    @comment = @post.comments.find(params[:id])
  end

  def comment_params
    params.require(:comment).permit(:content)
  end

  def authorize_comment!
    unless @comment.user == current_user || current_user.admin_or_moderator?
      redirect_to @post, alert: "You're not authorized to perform this action."
    end
  end

  def create_notification
    return if @post.user == current_user

    Notification.create(
      user: @post.user,
      actor: current_user,
      notifiable: @comment,
      notification_type: :new_comment
    )
  end

  def create_reply_notification
    return if @comment.user == current_user

    Notification.create(
      user: @comment.user,
      actor: current_user,
      notifiable: @reply,
      notification_type: :comment_reply
    )
  end
end


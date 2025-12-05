# frozen_string_literal: true

class ResharesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_post

  def create
    @reshare = current_user.reshares.find_or_initialize_by(post: @post)
    
    if @reshare.save
      respond_to do |format|
        format.html { redirect_back fallback_location: @post, notice: "Post reshared!" }
        format.turbo_stream
      end
    else
      redirect_back fallback_location: @post, alert: @reshare.errors.full_messages.join(", ")
    end
  end

  def destroy
    @reshare = current_user.reshares.find_by(post: @post)
    
    if @reshare&.destroy
      respond_to do |format|
        format.html { redirect_back fallback_location: @post, notice: "Reshare removed." }
        format.turbo_stream
      end
    else
      redirect_back fallback_location: @post, alert: "Unable to remove reshare."
    end
  end

  private

  def set_post
    @post = Post.friendly.find(params[:post_id])
  end
end

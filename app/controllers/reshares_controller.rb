# frozen_string_literal: true

class ResharesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_post

  def create
    @reshare = current_user.reshares.find_or_initialize_by(post: @post)
    thought_input = params.dig(:reshare, :thought).to_s.strip
    @reshare.thought = thought_input if thought_input.present?

    if @reshare.save
      msg = @reshare.with_thought? ? "Reposted with your thought." : "Post reshared!"
      respond_to do |format|
        format.html { redirect_back fallback_location: @post, notice: msg }
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

# frozen_string_literal: true

# /og/posts/<slug>.jpg?v=<version>: a breath's link-preview card (PostOgCard)
# for crawlers (WhatsApp, LinkedIn, X, Slack…). Public breaths only. If the
# card can't be drawn, the crawler gets the house card in the author's colour
# rather than an error.
class PostOgImagesController < ApplicationController
  def show
    post = Post.friendly.find(params[:id])
    return head(:not_found) unless post.visible_to?(nil)

    data = PostOgCard.new(post).jpeg
    expires_in 1.day, public: true
    request.session_options[:skip] = true
    send_data data, type: "image/jpeg", disposition: "inline", filename: "breath-#{post.id}.jpg"
  rescue ActiveRecord::RecordNotFound
    head :not_found
  rescue StandardError => e
    Rails.logger.warn("[og] card failed for #{params[:id]}: #{e.class}: #{e.message}")
    slug = post&.anonymous? ? AccentPalette::DEFAULT : post&.user&.accent_color
    redirect_to "/og/#{AccentPalette.valid?(slug) ? slug : AccentPalette::DEFAULT}.jpg"
  end
end

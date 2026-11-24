# frozen_string_literal: true

# The data behind "Snapshot for status" and "Share as thread" (ShareCard):
# fetched when the sheet opens, so the feed's cards carry none of it.
# Only breaths the whole world may read can be turned into images.
class ShareCardsController < ApplicationController
  member_rate_limit to: 60, within: 10.minutes, only: %i[show qr], name: "share-card", json: true

  def show
    post = Post.friendly.find(params[:id])
    return render(json: { error: "Only public breaths can be shared as images." }, status: :not_found) unless post.visible_to?(nil)

    card = ShareCard.new(post, sharer: current_user, urls: self)
    response.headers["Cache-Control"] = "private, no-store"
    render json: card.as_json(thread: params[:thread].present?, reply_ids: params[:replies].to_s.split(",").first(ShareCard::MAX_REPLIES))
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Breath not found" }, status: :not_found
  end

  # The QR code for a share menu without card data (a series): only for
  # addresses on this site.
  def qr
    url = URI.parse(params[:url].to_s)
    return head(:unprocessable_entity) unless url.is_a?(URI::HTTP) && url.host == request.host && params[:url].to_s.length <= 500

    render json: { qr: ShareCard.qr_modules(url.to_s) }
  rescue URI::InvalidURIError
    head :unprocessable_entity
  end
end

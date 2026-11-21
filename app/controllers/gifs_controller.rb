# frozen_string_literal: true

# JSON for the GIF picker. Klipy is called from here, never from the browser,
# so the API key stays on the server. Signed-in members only, rate limited.
#
#   GET /gifs?q=praise   search
#   GET /gifs/trending   what's popular now
class GifsController < ApplicationController
  before_action :authenticate_user!
  member_rate_limit to: 40, within: 1.minute, only: %i[index trending], name: "gifs-burst", json: true,
                    message: "Too many GIF searches. Wait a moment and try again."
  member_rate_limit to: 600, within: 1.hour, only: %i[index trending], name: "gifs-hourly", json: true,
                    message: "Too many GIF searches this hour. Please try again later."
  before_action :require_klipy

  def index
    respond_with_gifs { Klipy.search(params[:q], customer_id: customer_id, page: page) }
  end

  def trending
    respond_with_gifs { Klipy.trending(customer_id: customer_id, page: page) }
  end

  private

  def require_klipy
    head :not_found unless Klipy.configured?
  end

  def respond_with_gifs
    response.headers["Cache-Control"] = "private, no-store"
    render json: { results: yield }
  rescue Klipy::Error => e
    Rails.logger.warn("[GifsController] Klipy failed: #{e.message}")
    render json: { results: [], error: "GIFs aren't available right now. Please try again." }, status: :bad_gateway
  end

  def customer_id
    Klipy.customer_id_for(current_user)
  end

  def page
    params[:page].to_i.clamp(1, 20)
  end
end

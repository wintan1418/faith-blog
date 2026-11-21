# frozen_string_literal: true

# The GIF fields the picker adds to a message or comment form. They are only
# taken while GIFs are switched on (KLIPY_API_KEY set); the model checks the
# address is on Klipy's media CDN.
module GifParams
  extend ActiveSupport::Concern

  private

  def gif_params(scope)
    raw = params[scope]
    return {} unless Klipy.configured? && raw.is_a?(ActionController::Parameters)

    fields = raw.permit(:gif_url, :gif_width, :gif_height, :gif_title)
    fields[:gif_url].present? ? fields : {}
  end
end

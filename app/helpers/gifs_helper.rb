# frozen_string_literal: true

module GifsHelper
  # The GIF button shows only while Klipy is set up (KLIPY_API_KEY).
  def gifs_enabled?
    user_signed_in? && Klipy.configured?
  end

  # Width and height for showing a GIF no bigger than `max` on its longer side,
  # keeping its shape.
  def gif_display_size(record, max: 240)
    w = record.gif_width.to_i
    h = record.gif_height.to_i
    return [ max, max ] unless w.positive? && h.positive?

    scale = [ max.to_f / [ w, h ].max, 1.0 ].min
    [ (w * scale).round, (h * scale).round ]
  end
end

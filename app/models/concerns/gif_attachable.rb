# frozen_string_literal: true

# One GIF from Klipy on a message or a comment (gif_url, gif_width,
# gif_height, gif_title columns). Only addresses on Klipy's media CDN are
# accepted, so nobody can slip an arbitrary image URL into a chat or thread.
module GifAttachable
  extend ActiveSupport::Concern

  MAX_SIDE = 4_000

  included do
    before_validation :tidy_gif
    validate :gif_is_from_klipy
  end

  def has_gif?
    gif_url.present?
  end

  # Alt text for the image.
  def gif_alt
    gif_title.presence || "GIF"
  end

  private

  def tidy_gif
    self.gif_url = gif_url.to_s.strip.presence
    if gif_url.nil?
      self.gif_width = self.gif_height = self.gif_title = nil
      return
    end

    self.gif_title = gif_title.to_s.squish.first(140).presence
  end

  def gif_is_from_klipy
    return if gif_url.nil?
    return errors.add(:base, "That GIF can't be used. Please pick another.") unless gif_url.length <= 1_000 && Klipy.media_url?(gif_url)
    # Klipy's strictest rating is on, and a title with words we don't allow
    # still keeps the GIF out.
    return errors.add(:base, CleanLanguage::MESSAGE) if gif_title && CleanLanguage.offensive?(gif_title)

    [ gif_width, gif_height ].each do |side|
      next if side.nil? || (1..MAX_SIDE).cover?(side.to_i)

      errors.add(:base, "That GIF can't be used. Please pick another.")
      break
    end
  end
end

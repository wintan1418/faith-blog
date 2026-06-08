# frozen_string_literal: true

# Lightweight, gem-free Active Storage validation helpers. The app does not use
# active_storage_validations, so content-type and size are checked manually —
# matching the hand-rolled voice_note check that already lived on Post.
module AttachmentValidatable
  extend ActiveSupport::Concern

  IMAGE_CONTENT_TYPES = %w[
    image/jpeg image/jpg image/png image/webp image/gif image/heic image/heif
  ].freeze

  AUDIO_CONTENT_TYPES = %w[
    audio/webm audio/ogg audio/mpeg audio/mp3 audio/mp4 audio/aac audio/wav audio/x-m4a audio/m4a
  ].freeze

  private

  # Validates one or many attached images (works for has_one_attached and
  # has_many_attached). Skips blobs that aren't yet analyzed.
  def validate_image_attachment(name, max_bytes:)
    attachment = public_send(name)
    return unless attachment.attached?

    blobs_for(attachment).each do |blob|
      next unless blob

      if blob.content_type.present? && IMAGE_CONTENT_TYPES.exclude?(blob.content_type)
        errors.add(name, "must be a JPEG, PNG, WebP, or GIF image")
      end
      if blob.byte_size.to_i > max_bytes
        errors.add(name, "is too large (max #{max_bytes / 1.megabyte}MB)")
      end
    end
  end

  def validate_audio_attachment(name, max_bytes:)
    attachment = public_send(name)
    return unless attachment.attached?

    blob = attachment.blob
    return unless blob

    if blob.content_type.present? && AUDIO_CONTENT_TYPES.exclude?(blob.content_type)
      errors.add(name, "must be an audio recording")
    end
    if blob.byte_size.to_i > max_bytes
      errors.add(name, "is too large (max #{max_bytes / 1.megabyte}MB)")
    end
  end

  def blobs_for(attachment)
    if attachment.respond_to?(:blobs)
      attachment.blobs
    else
      [ attachment.blob ]
    end
  end
end

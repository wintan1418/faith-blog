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

  # Documents members may send in chats. Keyed by content type; the value is
  # the extensions we accept for it (the browser and the server must agree).
  DOCUMENT_TYPES = {
    "application/pdf" => %w[pdf],
    "application/msword" => %w[doc],
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document" => %w[docx],
    "application/vnd.ms-excel" => %w[xls],
    "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" => %w[xlsx],
    "application/vnd.ms-powerpoint" => %w[ppt],
    "application/vnd.openxmlformats-officedocument.presentationml.presentation" => %w[pptx],
    "application/vnd.oasis.opendocument.text" => %w[odt],
    "application/vnd.oasis.opendocument.spreadsheet" => %w[ods],
    "application/vnd.oasis.opendocument.presentation" => %w[odp],
    "application/rtf" => %w[rtf],
    "text/rtf" => %w[rtf],
    "text/plain" => %w[txt],
    "text/csv" => %w[csv],
    "application/epub+zip" => %w[epub]
  }.freeze
  DOCUMENT_EXTENSIONS = DOCUMENT_TYPES.values.flatten.uniq.freeze

  private

  def validate_document_attachment(name, max_bytes:, max_count:)
    attachment = public_send(name)
    return unless attachment.attached?

    blobs = blobs_for(attachment).compact
    errors.add(name, "can hold up to #{max_count} files") if blobs.size > max_count
    blobs.each do |blob|
      ext = File.extname(blob.filename.to_s).delete(".").downcase
      allowed = DOCUMENT_TYPES[blob.content_type.to_s]
      # Both must match: a renamed .exe or an HTML page called .pdf is refused.
      unless allowed&.include?(ext)
        errors.add(name, "must be a PDF, Word, Excel, PowerPoint, text or e-book file")
      end
      errors.add(name, "is too large (max #{max_bytes / 1.megabyte}MB)") if blob.byte_size.to_i > max_bytes
    end
  end

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

# frozen_string_literal: true

# Uploaded images, resized and compressed by Cloudinary's CDN (best format for the
# device, e.g. AVIF/WebP) instead of downloading the full original through our
# server. Anything not stored on Cloudinary (development, tests) uses the original.
module ImagesHelper
  # Profile photo cropped square around the face. `px` is the pixel size to fetch;
  # use about twice the displayed size so it stays sharp on phone screens.
  def avatar_src(profile, px = 96)
    resized_image_src(profile.avatar, width: px, height: px, crop: "fill", gravity: "face")
  end

  # A post or message photo, no wider than `width` (never upscaled).
  def photo_src(attachment, width: 1080)
    resized_image_src(attachment, width: width, crop: "limit")
  end

  def resized_image_src(attachment, width:, crop:, height: nil, gravity: nil)
    blob = attachment.try(:blob) || attachment
    return attachment unless blob.is_a?(ActiveStorage::Blob) && blob.image? && cloudinary_service?(blob.service)

    blob.service.url(
      blob.key, filename: blob.filename, content_type: blob.content_type,
      transformation: [ { width: width, height: height, crop: crop, gravity: gravity,
                          quality: "auto", fetch_format: "auto" }.compact ]
    )
  rescue StandardError => e
    Rails.logger.warn("[images] falling back to original: #{e.class}: #{e.message}")
    attachment
  end

  private

  def cloudinary_service?(service)
    service.class.name == "ActiveStorage::Service::CloudinaryService"
  end
end

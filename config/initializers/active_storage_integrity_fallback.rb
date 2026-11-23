# frozen_string_literal: true

# A stored file whose bytes no longer match its checksum (Cloudinary re-encoded
# an upload, Nov 2026) can't be resized: Active Storage raises IntegrityError and
# the page shows a 500 for that picture. Serve the original file instead, so a
# damaged thumbnail never breaks a page.
Rails.application.config.to_prepare do
  ActiveStorage::Representations::BaseController.class_eval do
    rescue_from ActiveStorage::IntegrityError do |error|
      Rails.logger.warn("[ActiveStorage] #{error.class} for blob #{@blob&.id}; serving the original")
      if @blob
        redirect_to @blob.url(disposition: :inline), allow_other_host: true
      else
        head :not_found
      end
    end
  end
end

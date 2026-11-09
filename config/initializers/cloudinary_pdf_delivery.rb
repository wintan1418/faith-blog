# frozen_string_literal: true

# Cloudinary stores PDFs as "image" files and, on accounts with "Allow
# delivery of PDF and ZIP files" switched off (the default), refuses to serve
# them from the normal URL (HTTP 401). That broke opening, downloading and
# sharing PDFs sent in chats.
#
# For PDFs only, hand out a short-lived signed download URL from Cloudinary's
# API instead. It works whatever that account setting is. Every other file
# keeps its normal URL; download links for photos and videos add Cloudinary's
# "attachment" flag so phones save the file instead of just showing it.
module CloudinaryPdfDelivery
  PDF_TYPES = %w[application/pdf application/postscript].freeze

  # Safe to call more than once, and before the Cloudinary service has loaded.
  def self.apply!
    return unless defined?(ActiveStorage::Service::CloudinaryService)

    service = ActiveStorage::Service::CloudinaryService
    service.prepend(self) unless service.ancestors.include?(self)
  end

  def url(key, filename: nil, content_type: "", **options)
    blob_key = find_blob_or_use_key(key)
    type = content_type.presence || (blob_key.respond_to?(:attributes) ? blob_key.attributes[:content_type] : nil)
    unless PDF_TYPES.include?(type.to_s)
      # A download link (photos, videos) should save the file, not just show it.
      attachment = options[:disposition].to_s.start_with?("attachment") && resource_type(nil, blob_key, type.to_s) != "raw"
      return attachment ? super(key, filename: filename, content_type: content_type, **options, flags: "attachment") : super
    end

    expires_in = options[:expires_in] || ActiveStorage.service_urls_expire_in || 5.minutes
    Cloudinary::Utils.private_download_url(
      full_public_id_internal(blob_key, options.except(:expires_in, :disposition, :filename, :content_type)),
      ext_for_file(blob_key, filename, type) || "pdf",
      resource_type: "image",
      type: "upload",
      attachment: options[:disposition].to_s.start_with?("attachment") || nil,
      expires_at: expires_in.from_now,
      cloud_name: @options[:cloud_name],
      api_key: @options[:api_key],
      api_secret: @options[:api_secret]
    )
  end
end

# The Cloudinary service file needs ActiveStorage::Blob, so load it (and patch
# it) once Blob is ready; after_initialize catches any other load order.
ActiveSupport.on_load(:active_storage_blob) do
  require "active_storage/service/cloudinary_service"
  CloudinaryPdfDelivery.apply!
end
Rails.application.config.after_initialize { CloudinaryPdfDelivery.apply! }

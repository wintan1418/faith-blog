# frozen_string_literal: true

# Active Storage's direct-upload endpoint (/rails/active_storage/direct_uploads)
# hands anyone a signed URL to put a file straight into our Cloudinary account.
# The only thing that uses it is the rich-text editor on breaths and comments,
# for photos. So: members only, photos only, 10 MB at most, and a sane rate,
# so the account can't be used as free file hosting.
module DirectUploadGuard
  CONTENT_TYPES = %w[image/jpeg image/png image/gif image/webp].freeze
  MAX_BYTES = 10.megabytes

  def self.included(base)
    base.before_action :require_member_for_direct_upload, only: :create
    base.before_action :require_allowed_direct_upload, only: :create
    base.rate_limit to: 30, within: 1.hour, only: :create, name: "direct-upload",
                    by: -> { warden.user(:user)&.id || request.remote_ip },
                    with: -> { render json: { error: "Too many uploads. Try again later." }, status: :too_many_requests },
                    store: RateLimitStore.store
  end

  private

  def require_member_for_direct_upload
    head :unauthorized unless warden.authenticate(scope: :user)
  end

  def require_allowed_direct_upload
    blob = params[:blob]
    type = blob.respond_to?(:[]) ? blob[:content_type].to_s : ""
    size = blob.respond_to?(:[]) ? blob[:byte_size].to_i : 0
    return if CONTENT_TYPES.include?(type) && size.positive? && size <= MAX_BYTES

    render json: { error: "Only photos up to #{MAX_BYTES / 1.megabyte} MB can be added here." }, status: :unprocessable_entity
  end
end

Rails.application.config.to_prepare do
  controller = ActiveStorage::DirectUploadsController
  controller.include(DirectUploadGuard) unless controller.include?(DirectUploadGuard)
end

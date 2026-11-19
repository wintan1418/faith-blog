# frozen_string_literal: true

# Rails 8 `rate_limit`, counted per member (per IP when signed out), with a
# kind reply in whatever format the endpoint speaks. Limits are set well above
# what a person does by hand, so only scripts and floods ever meet them.
module FriendlyRateLimits
  extend ActiveSupport::Concern

  DEFAULT_MESSAGE = "You're doing that a lot. Please wait a little and try again."

  class_methods do
    # json: true for endpoints only ever called by fetch(), whatever they Accept.
    def member_rate_limit(to:, within:, only:, name:, message: DEFAULT_MESSAGE, per: :member, json: false)
      rate_limit to: to, within: within, only: only, name: name, store: RateLimitStore.store,
                 by: (per == :ip ? -> { request.remote_ip } : -> { current_user&.id || request.remote_ip }),
                 with: -> { json ? render(json: { ok: false, error: message }, status: :too_many_requests) : rate_limited!(message) }
    end
  end

  private

  def rate_limited!(message = DEFAULT_MESSAGE)
    respond_to do |format|
      format.turbo_stream do
        flash.now[:alert] = message
        render turbo_stream: turbo_stream.update("flash_messages", partial: "shared/flash"), status: :too_many_requests
      end
      format.json { render json: { ok: false, error: message }, status: :too_many_requests }
      format.html do
        flash[:alert] = message
        redirect_back fallback_location: root_path, status: :see_other
      end
      format.any { render plain: message, status: :too_many_requests }
    end
  end
end

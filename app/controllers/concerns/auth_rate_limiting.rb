# frozen_string_literal: true

# Per-IP and per-email limits on the account endpoints (sign in, sign up,
# password reset, unlock) so passwords can't be guessed and addresses can't be
# probed at speed. Uses Rails 8's rate_limit with AuthThrottleStore.
module AuthRateLimiting
  extend ActiveSupport::Concern

  TOO_MANY_MESSAGE = "Too many attempts. Please wait a few minutes and try again."

  class_methods do
    def throttle_auth(only:, per_ip:, per_email:, within:)
      rate_limit to: per_ip, within: within, only: only, name: "ip",
                 store: AuthThrottleStore.store, with: -> { auth_rate_limited! }
      rate_limit to: per_email, within: within, only: only, name: "email",
                 by: -> { auth_rate_limit_email }, store: AuthThrottleStore.store, with: -> { auth_rate_limited! }
    end
  end

  private

  def auth_rate_limit_email
    email = params.dig(:user, :email).to_s.strip.downcase
    email.presence || "ip:#{request.remote_ip}"
  end

  def auth_rate_limited!
    Rails.logger.warn("[AuthRateLimit] #{controller_name}##{action_name} limited for ip=#{request.remote_ip}")
    respond_to do |format|
      format.json { render json: { error: TOO_MANY_MESSAGE }, status: :too_many_requests }
      format.any { render "shared/too_many_attempts", formats: :html, status: :too_many_requests }
    end
  end
end

# frozen_string_literal: true

# Sign in with Apple tokens, so a deleted account is also disconnected from the
# person's Apple ID (Apple requires this). On sign-in the iPhone app sends a
# one-time authorization code; we swap it for a refresh token and keep it. On
# account deletion we revoke that token.
#
# Uses the same .p8 key as push (it has Sign in with Apple enabled): APNS_KEY,
# APNS_KEY_ID (or APPLE_SIGN_IN_KEY_ID) and APNS_TEAM_ID (or APPLE_TEAM_ID).
module AppleSignInTokens
  class Error < StandardError; end

  TOKEN_URL  = URI("https://appleid.apple.com/auth/token")
  REVOKE_URL = URI("https://appleid.apple.com/auth/revoke")

  module_function

  def configured?
    key_id.present? && team_id.present? && ApnsKey.readable?
  end

  # One-time code from the app -> refresh token (nil if Apple says no).
  def exchange(code)
    return unless configured? && code.present?

    body = post(TOKEN_URL, grant_type: "authorization_code", code: code)
    body["refresh_token"]
  end

  def revoke(refresh_token)
    return false unless configured? && refresh_token.present?

    post(REVOKE_URL, token: refresh_token, token_type_hint: "refresh_token")
    true
  end

  def client_id = ENV.fetch("APPLE_BUNDLE_ID", "com.brethreign.app")
  def key_id    = (ENV["APPLE_SIGN_IN_KEY_ID"].presence || ENV["APNS_KEY_ID"]).to_s.strip.presence
  def team_id   = (ENV["APPLE_TEAM_ID"].presence || ENV["APNS_TEAM_ID"]).to_s.strip.presence

  # Short-lived JWT Apple accepts as our "client secret".
  def client_secret
    now = Time.now.to_i
    JWT.encode({ iss: team_id, iat: now, exp: now + 300, aud: "https://appleid.apple.com", sub: client_id },
               OpenSSL::PKey.read(ApnsKey.pem), "ES256", { kid: key_id })
  end

  def post(url, params)
    response = Net::HTTP.post_form(url, params.merge(client_id: client_id, client_secret: client_secret))
    raise Error, "Apple #{url.path}: #{response.code} #{response.body.to_s.first(200)}" unless response.is_a?(Net::HTTPSuccess)

    response.body.present? ? JSON.parse(response.body) : {}
  end
end

# frozen_string_literal: true

# Checks a "Sign in with Apple" identity token from the iPhone app: signed by
# one of Apple's published keys, issued by Apple, for our app, not expired.
class AppleIdentityToken
  class Invalid < StandardError; end

  ISSUER = "https://appleid.apple.com"
  KEYS_URL = URI("https://appleid.apple.com/auth/keys")

  def self.audiences
    [ ENV.fetch("APPLE_BUNDLE_ID", "com.brethreign.app"), ENV["APPLE_SERVICES_ID"] ].compact_blank
  end

  # Returns the token's claims ("sub", "email", "email_verified", …).
  def self.verify(token)
    claims, = JWT.decode(token.to_s, nil, true,
                         algorithms: [ "RS256" ], jwks: method(:jwks),
                         iss: ISSUER, verify_iss: true,
                         aud: audiences, verify_aud: true)
    claims
  rescue JWT::DecodeError => e
    raise Invalid, e.message
  end

  # Apple rotates its keys now and then: on a key we don't know, fetch again.
  def self.jwks(options = {})
    Rails.cache.delete("apple_auth_keys") if options[:kid_not_found]
    keys = Rails.cache.fetch("apple_auth_keys", expires_in: 12.hours) do
      JSON.parse(Net::HTTP.get(KEYS_URL))
    end
    JWT::JWK::Set.new(keys)
  end
end

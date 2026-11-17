# frozen_string_literal: true

# Revokes a deleted account's Sign in with Apple token (see AppleSignInTokens).
class AppleTokenRevokeJob < ApplicationJob
  queue_as :default
  retry_on AppleSignInTokens::Error, Net::OpenTimeout, Net::ReadTimeout, wait: :polynomially_longer, attempts: 5

  def perform(refresh_token)
    AppleSignInTokens.revoke(refresh_token)
  end
end

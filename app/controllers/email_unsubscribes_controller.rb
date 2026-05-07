# frozen_string_literal: true

# Token-signed unsubscribe endpoints — let users opt out of digest emails
# from a one-click link without having to log in. Tokens are scoped per
# email type so opting out of digests doesn't kill transactional mail.
class EmailUnsubscribesController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  layout "application"

  def weekly_digest
    user_id = Rails.application.message_verifier(:weekly_digest_unsubscribe)
                   .verify(params[:token], purpose: nil)
    user = User.find_by(id: user_id)
    if user
      user.update_column(:email_notifications_enabled, false)
      @result = :ok
      @user = user
    else
      @result = :missing
    end
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    @result = :invalid
  end
end

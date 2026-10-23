# frozen_string_literal: true

# Google sign-in for the mobile apps. Google blocks its web sign-in inside app
# web views, so the app signs in with the phone's native Google account picker
# and posts the resulting ID token here (from inside the web view, so the
# session cookie lands where the app needs it).
class Users::NativeGoogleSessionsController < ApplicationController
  # The app's "Continue with Google" button points here. New app versions catch
  # this link and show the native picker; an older version that doesn't just
  # lands back on the sign-in page.
  def start
    redirect_to new_user_session_path,
                alert: "Update the Brethreign app to sign in with Google, or use your email and password."
  end

  def create
    payload = Google::Auth::IDTokens.verify_oidc(params.require(:id_token), aud: self.class.audiences)
    return render(json: { error: "Your Google email isn't verified." }, status: :unauthorized) unless payload["email_verified"]

    user = User.from_google(google_auth(payload))
    unless user.active_for_authentication?
      return render json: { error: I18n.t("devise.failure.#{user.inactive_message}", default: "This account can't sign in.") },
                    status: :forbidden
    end

    sign_in(user, event: :authentication)
    render json: { location: after_sign_in_path_for(user) }
  rescue Google::Auth::IDTokens::VerificationError, ActionController::ParameterMissing
    render json: { error: "Google sign in could not be completed. Please try again." }, status: :unauthorized
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  # ID tokens from the apps are issued for our web client (Android) or the iOS client.
  def self.audiences
    [ ENV["GOOGLE_CLIENT_ID"], ENV["GOOGLE_IOS_CLIENT_ID"] ].compact_blank
  end

  private

  def google_auth(payload)
    OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: payload["sub"],
      info: { email: payload["email"], name: payload["name"] }
    )
  end
end

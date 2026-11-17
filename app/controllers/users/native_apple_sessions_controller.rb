# frozen_string_literal: true

# Sign in with Apple for the iPhone app. The Rails button links to start; the
# app catches that link, shows Apple's sheet, and posts the identity token here
# from inside the web view (so the session cookie lands where the app needs it).
class Users::NativeAppleSessionsController < ApplicationController
  # An app version that can't sign in with Apple just lands back on sign-in.
  def start
    redirect_to new_user_session_path,
                alert: "Update the Brethreign app to sign in with Apple, or use your email and password."
  end

  def create
    claims = AppleIdentityToken.verify(params.require(:identity_token))
    email = claims["email"].to_s.downcase
    user = User.find_by(provider: "apple", uid: claims["sub"])
    if user.nil?
      return refuse("Apple didn't share an email for this account.", :unauthorized) if email.blank?
      return refuse("Your Apple email isn't verified.", :unauthorized) unless verified?(claims)

      user = User.from_google(apple_auth(claims["sub"], email))
    end

    unless user.active_for_authentication?
      return refuse(I18n.t("devise.failure.#{user.inactive_message}", default: "This account can't sign in."), :forbidden)
    end

    sign_in(user, event: :authentication)
    render json: { location: after_sign_in_path_for(user) }
  rescue AppleIdentityToken::Invalid, ActionController::ParameterMissing
    refuse("Apple sign in could not be completed. Please try again.", :unauthorized)
  rescue ActiveRecord::RecordInvalid => e
    refuse(e.record.errors.full_messages.to_sentence, :unprocessable_entity)
  end

  private

  def refuse(message, status)
    flash[:alert] = message
    render json: { location: new_user_session_path, error: message }, status: status
  end

  def verified?(claims)
    [ true, "true" ].include?(claims["email_verified"])
  end

  # Apple gives the person's name only on their very first sign-in, and only to
  # the app, which passes it along.
  def apple_auth(uid, email)
    name = [ params[:given_name], params[:family_name] ].compact_blank.join(" ").presence
    OmniAuth::AuthHash.new(provider: "apple", uid: uid, info: { email: email, name: name })
  end
end

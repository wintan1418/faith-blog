# frozen_string_literal: true

class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def google_oauth2
    # Opened directly (no Google answer attached), there is no one to sign in.
    auth = request.env["omniauth.auth"]
    return failure if auth.blank?

    @user = User.from_google(auth)

    if @user.persisted?
      session[:ad_signup] = true if @user.previously_new_record? # a new account, for ads measurement
      set_flash_message(:notice, :success, kind: "Google") if is_navigational_format?
      sign_in_and_redirect @user, event: :authentication
    else
      redirect_to new_user_registration_path, alert: @user.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to new_user_registration_path, alert: e.record.errors.full_messages.to_sentence
  end

  def failure
    redirect_to new_user_session_path, alert: "Google sign in could not be completed. Please try again."
  end
end

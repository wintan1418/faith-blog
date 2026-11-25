# frozen_string_literal: true

class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  include SignInChecks

  def google_oauth2
    # Opened directly (no Google answer attached), there is no one to sign in.
    auth = request.env["omniauth.auth"]
    return failure if auth.blank?

    @user = User.from_google(auth)

    if @user.persisted?
      if @user.previously_new_record?
        session[:ad_signup] = true # a new account, for ads measurement
        InviteAttribution.apply!(@user, cookies)
      end
      # Two-step login still asks for the authenticator code.
      if @user.active_for_authentication? && (check_path = begin_sign_in_check(@user, method: "google"))
        return redirect_to(check_path)
      end

      set_flash_message(:notice, :success, kind: "Google") if is_navigational_format?
      request.env[AccountDevices::SIGN_IN_OPTIONS] = { method: @user.previously_new_record? ? "signup" : "google" }
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

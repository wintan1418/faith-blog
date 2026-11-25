# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  include AuthRateLimiting
  include GuestReturnTo

  BOT_REJECTION_MESSAGE = "We couldn't create your account just now. Please try again."

  # A church or family can share one network, so the per-IP limit is roomy.
  throttle_auth only: :create, per_ip: 10, per_email: 5, within: 1.hour
  before_action :reject_bots!, only: :create
  before_action :store_invite_token, only: [ :new, :create ]
  before_action :configure_sign_up_params, only: [ :create ]
  before_action :configure_account_update_params, only: [ :update ]

  def new
    invitation = Invitation.find_pending_by_token(session[:invitation_token])
    build_resource(email: invitation&.email)
    @inviter = InviteAttribution.inviter_from(cookies)
    respond_with resource
  end

  def create
    request.env[AccountDevices::SIGN_IN_OPTIONS] = { method: "signup" }
    super do |resource|
      if resource.persisted?
        # "Check your email": a code (and a one-tap link) to verify the address.
        EmailVerification.send_code(resource, request: request)
        # Default new accounts to "stay signed in" — same UX as LinkedIn / X.
        # The session cookie is 6mo (config/initializers/session_store.rb)
        # and the remember-me cookie extends every visit.
        resource.remember_me = true
        session[:ad_signup] = true # counted as a sign-up for ads (shared/_ad_tracking)
        accept_invitation_for(resource)
        InviteAttribution.apply!(resource, cookies)
      end
    end
  end

  # Email and password changes go through Settings → Account (current
  # password, a code to the new address, security emails); Devise's own
  # /users/edit form would skip all of that.
  def edit
    redirect_to edit_settings_account_path
  end

  def update
    redirect_to edit_settings_account_path, status: :see_other
  end

  # Devise's own DELETE /users removed the account at once: no typed-username
  # check and no Sign in with Apple revoke. Accounts are deleted only from
  # Settings → Account, which does both.
  def destroy
    redirect_to delete_settings_account_path, status: :see_other
  end

  protected

  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :username ])
  end

  def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [ :username ])
  end

  # Web: "Check your email" (the code screen), then wherever they were going.
  # The apps reload every tab on sign-in, so they land on the feed, where the
  # verify banner leads to the same screen.
  def after_sign_up_path_for(resource)
    stored = stored_location_for(resource)
    return feed_path if hotwire_native_app?

    email_verification_path(return_to: stored.presence)
  end

  def after_inactive_sign_up_path_for(resource)
    new_user_session_path
  end

  private

  # Honeypot, minimum fill time and (when configured) Turnstile — see
  # SignupGuard. A rejected request just sees the form again.
  def reject_bots!
    reason = SignupGuard.bot_reason(params, remote_ip: request.remote_ip)
    return unless reason

    SignupGuard.record_block!(reason, where: "sign-up", remote_ip: request.remote_ip, email: nested_param(:user, :email))
    build_resource(optional_params(:user).permit(:username, :email))
    resource.errors.add(:base, BOT_REJECTION_MESSAGE)
    render :new, status: :unprocessable_entity
  end

  def store_invite_token
    session[:invitation_token] = params[:invite] if params[:invite].present?
  end

  def accept_invitation_for(resource)
    invitation = Invitation.find_pending_by_token(session.delete(:invitation_token))
    return unless invitation && invitation.email.casecmp?(resource.email)

    invitation.accept!(resource)
  end
end

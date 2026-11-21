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
    respond_with resource
  end

  def create
    super do |resource|
      if resource.persisted?
        # Default new accounts to "stay signed in" — same UX as LinkedIn / X.
        # The session cookie is 6mo (config/initializers/session_store.rb)
        # and the remember-me cookie extends every visit.
        resource.remember_me = true
        session[:ad_signup] = true # counted as a sign-up for ads (shared/_ad_tracking)
        accept_invitation_for(resource)
      end
    end
  end

  protected

  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :username ])
  end

  def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [ :username ])
  end

  def after_sign_up_path_for(resource)
    stored = stored_location_for(resource)
    return feed_path if hotwire_native_app?

    stored || feed_path
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

    SignupGuard.record_block!(reason, where: "sign-up", remote_ip: request.remote_ip, email: params.dig(:user, :email))
    build_resource(params.fetch(:user, {}).permit(:username, :email))
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

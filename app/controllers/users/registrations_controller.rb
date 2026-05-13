# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
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
    feed_path
  end

  def after_inactive_sign_up_path_for(resource)
    new_user_session_path
  end

  private

  def store_invite_token
    session[:invitation_token] = params[:invite] if params[:invite].present?
  end

  def accept_invitation_for(resource)
    invitation = Invitation.find_pending_by_token(session.delete(:invitation_token))
    return unless invitation && invitation.email.casecmp?(resource.email)

    invitation.accept!(resource)
  end
end

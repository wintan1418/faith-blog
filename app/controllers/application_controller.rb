# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pagy::Backend

  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :touch_last_seen,                 if: :user_signed_in?

  helper_method :current_user_admin?, :current_user_moderator?, :current_user_super_admin?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [ :username ])
    devise_parameter_sanitizer.permit(:account_update, keys: [ :username ])
  end

  def authenticate_admin!
    redirect_to root_path, alert: "Access denied." unless current_user&.super_admin? || current_user&.admin?
  end

  def authenticate_super_admin!
    redirect_to root_path, alert: "Access denied." unless current_user&.super_admin?
  end

  def authenticate_moderator!
    redirect_to root_path, alert: "Access denied." unless current_user&.admin_or_moderator?
  end

  def current_user_admin?
    current_user&.super_admin? || current_user&.admin?
  end

  def current_user_moderator?
    current_user&.admin_or_moderator?
  end

  def current_user_super_admin?
    current_user&.super_admin?
  end

  def after_sign_in_path_for(resource)
    stored_location_for(resource) || feed_path
  end

  def after_sign_out_path_for(_resource_or_scope)
    root_path
  end

  # Refresh user's last_seen_at on each authenticated request, but
  # throttle to once a minute so we don't write on every page hit.
  def touch_last_seen
    return unless current_user

    last = current_user.last_seen_at
    return if last.present? && last > 1.minute.ago

    current_user.update_column(:last_seen_at, Time.current)
  end
end

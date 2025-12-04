# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pagy::Backend

  before_action :configure_permitted_parameters, if: :devise_controller?

  helper_method :current_user_admin?, :current_user_moderator?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: [:username])
    devise_parameter_sanitizer.permit(:account_update, keys: [:username])
  end

  def authenticate_admin!
    redirect_to root_path, alert: "Access denied." unless current_user&.admin?
  end

  def authenticate_moderator!
    redirect_to root_path, alert: "Access denied." unless current_user&.admin_or_moderator?
  end

  def current_user_admin?
    current_user&.admin?
  end

  def current_user_moderator?
    current_user&.admin_or_moderator?
  end

  def after_sign_in_path_for(resource)
    stored_location_for(resource) || feed_path
  end

  def after_sign_out_path_for(_resource_or_scope)
    root_path
  end
end

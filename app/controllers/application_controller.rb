# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Pagy::Backend

  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :touch_last_seen,                 if: :user_signed_in?
  before_action :require_supported_app_version
  after_action :track_page_view

  helper_method :current_user_admin?, :current_user_moderator?, :current_user_super_admin?

  # Stale CSRF tokens (page cached with old token, session expired, etc.)
  # used to dump the 422 backtrace at the user — which looked like a server
  # error. Send them to sign-in if they're not authenticated, otherwise
  # bounce them back to where they came from with a friendly hint.
  rescue_from ActionController::InvalidAuthenticityToken do
    if user_signed_in?
      redirect_back fallback_location: root_path,
                    alert: "That action expired — please try again."
    else
      session[:user_return_to] = request.referer if request.referer.present?
      redirect_to new_user_session_path,
                  alert: "Your session expired. Sign in again to continue."
    end
  end

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
    stored = stored_location_for(resource)
    # The mobile apps always land on the feed; they reload every tab after sign-in.
    return feed_path if hotwire_native_app?

    stored || feed_path
  end

  def after_sign_out_path_for(_resource_or_scope)
    root_path
  end

  # Refresh user's last_seen_at on each authenticated request, but
  # throttle to once a minute so we don't write on every page hit.
  def touch_last_seen
    return unless current_user

    record_app_version
    last = current_user.last_seen_at
    return if last.present? && last > 1.minute.ago

    current_user.update_column(:last_seen_at, Time.current)
  end

  # Remember which Android app version a member uses, so Admin → App versions can show who is behind.
  def record_app_version
    version = helpers.android_app_version&.to_s
    return if version.nil? || current_user.android_app_version == version

    current_user.update_column(:android_app_version, version)
  end

  APP_VERSION_EXEMPT = %w[pages well_known configurations push_devices rails/health].freeze

  # An app older than the minimum version sees "Update required" instead of the page.
  def require_supported_app_version
    return unless request.get? && request.format.html?
    return if controller_path.in?(APP_VERSION_EXEMPT)
    return unless helpers.android_update_required?

    render "app_updates/required", layout: false
  end

  # One "$view" per page someone opens, for Admin → Dashboard. Skips admin pages,
  # frames, background requests and Turbo's hover prefetches.
  def track_page_view
    return unless request.get? && request.format.html? && response.successful?
    return if controller_path.start_with?("admin/") || turbo_frame_request? || request.xhr?
    return if [ request.headers["Sec-Purpose"], request.headers["X-Sec-Purpose"], request.headers["Purpose"] ].join(" ").include?("prefetch")

    ahoy.track "$view", path: request.path, page: "#{controller_path}##{action_name}"
  rescue StandardError => e
    Rails.logger.warn("[ahoy] #{e.class}: #{e.message}")
  end
end

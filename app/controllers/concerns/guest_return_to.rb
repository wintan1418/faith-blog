# frozen_string_literal: true

# When a signed-out visitor taps something on the site, the "join to continue"
# dialog (guest_gate_controller.js) sends them to sign up or sign in with
# ?return_to=/the/page/they/tapped. We remember that page so they land on it
# once they have an account, instead of on the feed. Google sign-in keeps it
# too: it's stored in the session, which survives the round trip.
module GuestReturnTo
  extend ActiveSupport::Concern

  included do
    before_action :remember_guest_return_to, only: :new
  end

  # Only paths on this site, never the auth pages themselves.
  def self.safe_path(value)
    path = value.to_s
    return if path.blank? || path.length > 500
    return unless path.start_with?("/") && !path.start_with?("//") && !path.include?("\\")
    return if path.match?(%r{\A/(users|auth)(/|\?|\z)})

    uri = URI.parse(path)
    return if uri.host || uri.scheme
    return if uri.path == "/" # the welcome page or the guest feed: the default landing is better

    path
  rescue URI::InvalidURIError
    nil
  end

  private

  def remember_guest_return_to
    path = GuestReturnTo.safe_path(params[:return_to])
    store_location_for(:user, path) if path
  end
end

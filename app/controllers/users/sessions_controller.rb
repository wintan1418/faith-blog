# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  include AuthRateLimiting

  # Lockable locks an account after 10 wrong passwords; this stops one IP
  # spraying many accounts and slows guessing at a single one.
  throttle_auth only: :create, per_ip: 10, per_email: 10, within: 5.minutes

  def after_sign_in_path_for(resource)
    stored = stored_location_for(resource)
    # The mobile apps always land on the feed; they reload every tab after sign-in.
    return feed_path if hotwire_native_app?

    stored || feed_path
  end

  def after_sign_out_path_for(_resource_or_scope)
    root_path
  end
end

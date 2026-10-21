# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
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

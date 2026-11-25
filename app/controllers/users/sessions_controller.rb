# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  include AuthRateLimiting
  include GuestReturnTo
  include SignInChecks

  # Lockable locks an account after 10 wrong passwords; this stops one IP
  # spraying many accounts and slows guessing at a single one.
  throttle_auth only: :create, per_ip: 10, per_email: 10, within: 5.minutes

  # These ask "who's signed in?", which on this POST would run the password
  # check and sign in before #create decides whether a sign-in check is due.
  skip_before_action :check_device_session, :set_current_viewer, :touch_last_seen, only: :create
  skip_after_action :deliver_seeds_toast, only: :create
  # Devise lets the password strategy run for the whole request; then any
  # page rendered first (the "too many attempts" page from the rate limit)
  # asked "who's signed in?" and signed them in anyway. Allow it only inside
  # #create, after the rate limits.
  skip_before_action :allow_params_authentication!, only: :create

  # Devise's password check (wrong-password counting, lockable, paranoid
  # messages) runs exactly as before. When the password is right, a sign-in
  # from an unrecognised device or with two-step login on stops at the
  # sign-in check (SignInChecks) instead of signing in straight away.
  def create
    # Warden's own (cached) instance, so nothing later in this request runs
    # the password check a second time (which would count a wrong password twice).
    allow_params_authentication!
    strategy = warden.send(:_fetch_strategy, :database_authenticatable, resource_name)
    return super unless strategy&.valid? && !strategy.performed?

    strategy._run!
    throw :warden, auth_options.merge(message: strategy.message || :invalid) unless strategy.successful?

    user = strategy.user
    unless user.active_for_authentication?
      throw :warden, auth_options.merge(message: user.inactive_message)
    end

    if (check_path = begin_sign_in_check(user, method: "password", remember: user.remember_me))
      return redirect_to(check_path, status: :see_other)
    end

    self.resource = user
    request.env[AccountDevices::SIGN_IN_OPTIONS] = { method: "password" }
    set_flash_message!(:notice, :signed_in)
    sign_in(resource_name, resource)
    respond_with resource, location: after_sign_in_path_for(resource)
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
end

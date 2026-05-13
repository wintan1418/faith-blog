# frozen_string_literal: true

# Persistent session cookie — keep users signed in across browser restarts
# (LinkedIn / X feel). Without `expire_after`, the cookie is session-only
# and clears the moment the browser closes; that's why people were
# getting bounced back to the sign-in page over and over.
Rails.application.config.session_store :cookie_store,
  key: "_brethreign_session",
  expire_after: 6.months,
  same_site: :lax,
  secure: Rails.env.production?,
  httponly: true

# frozen_string_literal: true

# A phone or browser a member has signed in on (Settings → Security → Devices).
#
#   verified_at    — recognised: password sign-ins here skip the emailed code
#   trusted_until  — two-step login skips the authenticator code until then
#   session_digest — hash of the token in the session signed in here now;
#                    nil once the device is signed out
class UserDevice < ApplicationRecord
  TRUST_FOR = 30.days
  TOUCH_EVERY = 5.minutes

  belongs_to :user

  scope :signed_in, -> { where.not(session_digest: nil).where(signed_out_at: nil) }
  scope :by_recent, -> { order(Arel.sql("COALESCE(last_active_at, signed_in_at, created_at) DESC")) }

  def recognised? = verified_at.present?
  def trusted? = trusted_until.present? && trusted_until.future?
  def signed_in? = session_digest.present? && signed_out_at.nil?
  def app? = platform.in?(%w[ios_app android_app])

  def last_active = last_active_at || signed_in_at || created_at

  # Signed out remotely: the device forgets its session, and is no longer
  # recognised or trusted (whoever holds it must prove themselves again).
  def sign_out!(forget: true)
    attrs = { session_digest: nil, signed_out_at: Time.current }
    attrs.merge!(verified_at: nil, trusted_until: nil) if forget
    update_columns(attrs.merge(updated_at: Time.current))
    remove_push_token!
  end

  def remove_push_token!
    return if push_token.blank?

    ApplicationPushDevice.where(owner: user, token: push_token).destroy_all
    update_column(:push_token, nil)
  rescue StandardError => e
    Rails.logger.warn("[UserDevice##{id}] push token removal failed: #{e.class}: #{e.message}")
  end
end

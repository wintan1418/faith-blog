# frozen_string_literal: true

# The personal invite link (brethreign.com/join/username): a visitor who opens
# it carries a signed cookie naming the member who shared it for 30 days, and
# when they create an account (email form, Google on the web, or Google in
# the apps) users.invited_by_id is set from it. An accepted email invitation
# already set invited_by_id (User#accept_pending_invitations) and wins.
#
# The inviter's seeds are paid later, once the new member is real: see
# Seeds.invite_joined.
module InviteAttribution
  COOKIE = :br_invited_by
  TTL = 30.days
  # Only the account made in this sign-up is attributed, never an existing
  # one signing in with Google.
  NEW_ACCOUNT_WINDOW = 1.hour

  module_function

  def remember(cookies, inviter)
    cookies.signed[COOKIE] = { value: inviter.id, expires: TTL.from_now, httponly: true, same_site: :lax }
  end

  # The inviter named by the cookie, if they can still invite.
  def inviter_from(cookies)
    id = cookies.signed[COOKIE]
    return if id.blank?

    inviter = User.includes(:profile).find_by(id: id)
    inviter if inviter&.can_invite_by_link?
  rescue StandardError
    nil
  end

  # Called right after sign-up. Returns the inviter when the new member was
  # attributed to them. Never raises: a sign-up must never fail over this.
  def apply!(user, cookies)
    return unless user&.persisted?

    inviter = inviter_from(cookies)
    cookies.delete(COOKIE) if cookies.signed[COOKIE].present?
    return unless inviter
    return if inviter.id == user.id
    return unless user.created_at && user.created_at > NEW_ACCOUNT_WINDOW.ago

    user.reload
    return if user.invited_by_id.present? || user.accepted_invitations.exists?

    user.update_column(:invited_by_id, inviter.id)
    inviter
  rescue StandardError => e
    Rails.logger.warn("[InviteAttribution] user #{user&.id}: #{e.class}: #{e.message}")
    nil
  end
end

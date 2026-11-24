# frozen_string_literal: true

# Shared breaths carry who shared them: every share link and QR code ends in
# ?ref=<username> (or /b/<code>/<username>). When a signed-out visitor lands
# on a breath with a valid ref, the page greets them ("Ada invited you to the
# conversation") and the sharer is remembered through the personal invite
# cookie (InviteAttribution), so an account made later is credited to them
# and Seeds.invite_joined pays them once the newcomer posts.
#
# What keeps it honest:
# - Only members who may invite by link are named or credited: active, adult,
#   not restricted, suspended or banned (User#can_invite_by_link?). Checked
#   again at sign-up and again when Seeds pay.
# - The first inviter wins: a ref never replaces a remembered invite, so
#   links can't be used to snatch someone else's credit.
# - Each address can only set the cookie a handful of times per window.
# - The author of an anonymous breath is never named on it, even by their own
#   link.
# - Lookups are cached for a few minutes (and a cache failure only costs one
#   indexed query), so a guest's page stays fast.
module ShareReferral
  FORMAT = /\A[A-Za-z0-9_]{3,30}\z/
  LOOKUP_TTL = 5.minutes
  CAPTURE_LIMIT = 20
  CAPTURE_WINDOW = 10.minutes

  Sharer = Data.define(:id, :username, :display_name)

  module_function

  # The member a ref names, if they may be shown and credited; nil otherwise.
  def sharer_for(ref)
    ref = ref.to_s
    return unless ref.match?(FORMAT)

    cached = cache_read(ref)
    return cached.presence && Sharer.new(**cached.symbolize_keys) unless cached.nil?

    sharer = lookup(ref)
    cache_write(ref, sharer ? sharer.to_h.transform_keys(&:to_s) : {})
    sharer
  end

  # Called on a breath page for a signed-out visitor. Returns the Sharer to
  # greet them with, or nil.
  def capture(cookies:, post:, ref:, ip:)
    sharer = sharer_for(ref)
    return unless sharer
    return if post.anonymous? && post.user_id == sharer.id

    remember(cookies, sharer, ip)
    sharer
  end

  # The ref a member's share links carry, or nil when there should be none:
  # signed out, not allowed to invite, or the author of an anonymous breath
  # (their name next to it would unmask them).
  def ref_for(sharer, post)
    return unless sharer
    return if post&.anonymous? && post.user_id == sharer.id
    return unless sharer.can_invite_by_link?

    sharer.username
  end

  def remember(cookies, sharer, ip)
    return if cookies.signed[InviteAttribution::COOKIE].present? && InviteAttribution.inviter_from(cookies)
    return unless within_capture_limit?(ip)

    InviteAttribution.remember(cookies, sharer)
  end

  def within_capture_limit?(ip)
    count = RateLimitStore.store.increment("share-ref:#{ip}", 1, expires_in: CAPTURE_WINDOW)
    count.nil? || count <= CAPTURE_LIMIT
  rescue StandardError => e
    Rails.logger.warn("[ShareReferral] rate limit store failed: #{e.class}: #{e.message}")
    true
  end

  def lookup(ref)
    user = User.active.includes(:profile, :risk_profile).find_by(username: ref)
    return unless user&.can_invite_by_link?

    Sharer.new(id: user.id, username: user.username, display_name: user.display_name)
  end

  def cache_key(ref) = "share-ref/v1/#{ref}"

  def cache_read(ref)
    Rails.cache.read(cache_key(ref))
  rescue StandardError => e
    Rails.logger.warn("[ShareReferral] cache read failed: #{e.class}: #{e.message}")
    nil
  end

  def cache_write(ref, value)
    Rails.cache.write(cache_key(ref), value, expires_in: LOOKUP_TTL)
  rescue StandardError => e
    Rails.logger.warn("[ShareReferral] cache write failed: #{e.class}: #{e.message}")
    nil
  end
end

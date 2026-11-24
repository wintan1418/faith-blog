# frozen_string_literal: true

# "Come join the conversation": the page behind a member's personal invite
# link, brethreign.com/join/username. Shows who invited you, a few live public
# conversations and a Join button, and remembers the inviter for 30 days so
# the account made later is attributed to them (InviteAttribution).
#
# An unknown, deactivated or under-18 inviter gets the same page without
# anyone's name on it (and no attribution). Members who open a link go to
# their feed.
class JoinsController < ApplicationController
  # A church or office can share one address, so the limit is roomy; it only
  # has to stop someone scraping who invited whom.
  PAGE_LIMIT = 60
  PAGE_WINDOW = 5.minutes
  SNIPPETS = 3

  before_action :throttle_by_ip

  def show
    return redirect_to(feed_path) if user_signed_in?

    @inviter = User.active.includes(profile: { avatar_attachment: :blob })
                   .find_by("LOWER(users.username) = ?", params[:username].to_s.downcase)
    @inviter = nil unless @inviter&.can_invite_by_link?
    InviteAttribution.remember(cookies, @inviter) if @inviter
    @snippets = snippets
    @join_url = @inviter ? join_invite_url(@inviter.username) : join_invite_url("brethreign")
    render formats: :html, content_type: "text/html"
  end

  private

  # Counted in the app cache; if the cache is down the page still opens.
  def throttle_by_ip
    count = RateLimitStore.store.increment("join-page:#{request.remote_ip}", 1, expires_in: PAGE_WINDOW)
    return unless count && count > PAGE_LIMIT

    render plain: "Too many requests. Please try again in a few minutes.", status: :too_many_requests
  rescue StandardError => e
    Rails.logger.warn("[joins] rate limit store failed: #{e.class}: #{e.message}")
  end

  # A few recent, well-loved public breaths: live and approved, in a public
  # room (or none), named (never anonymous), not prayer requests, by active
  # adult members with public profiles.
  def snippets
    authors = User.active.joins(:profile).where(profiles: { public_profile: true }).merge(Profile.adults_or_unknown)
    rooms = Room.public_rooms.select(:id)
    Post.published.named
        .where(prayer_status: :not_a_prayer)
        .where("posts.room_id IS NULL OR posts.room_id IN (#{rooms.to_sql})")
        .where(user_id: authors.select(:id))
        .where(published_at: 60.days.ago..)
        .includes(:rich_text_content, :room, user: { profile: { avatar_attachment: :blob } })
        .order(Arel.sql("(posts.likes_count * 2 + posts.comments_count * 3 + posts.views_count * 0.1) DESC, posts.published_at DESC"))
        .limit(SNIPPETS * 3)
        .select { |post| post.content.to_plain_text.squish.length >= 40 }
        .uniq(&:user_id)
        .first(SNIPPETS)
  rescue StandardError => e
    Rails.logger.warn("[joins] snippets failed: #{e.class}: #{e.message}")
    []
  end
end

# frozen_string_literal: true

# Everything the "Snapshot for status" / "Share as thread" sheet needs to draw
# a breath as an image (share_card_renderer.js does the drawing): the author,
# the words, the first photo, real counts, the date, the series line, and a
# short link + QR code that carry the sharer's ref (ShareReferral).
#
# Only for breaths the whole world may read. Privacy rules live here, not in
# the browser:
# - An anonymous breath shows "Anonymous": no name, handle, avatar or colour.
# - Thread replies: only live, approved, unflagged comments with words in
#   them, by active adult members who haven't been restricted, and never by
#   anyone the sharer has blocked or who has blocked the sharer. The author of
#   an anonymous breath stays anonymous in the replies too.
class ShareCard
  TEXT_LIMIT = 2_400
  REPLY_TEXT_LIMIT = 900
  MAX_REPLIES = 4
  CANDIDATE_REPLIES = 8

  Author = Data.define(:anonymous, :name, :username, :initial, :avatar_url, :verified, :founder)

  # Rows of "0"/"1" for the canvas to draw (medium error correction).
  def self.qr_modules(value)
    RQRCode::QRCode.new(value, level: :m).modules.map { |row| row.map { |on| on ? "1" : "0" }.join }
  end

  def initialize(post, sharer:, urls:)
    @post = post
    @sharer = sharer
    @urls = urls
  end

  def as_json(thread: false, reply_ids: nil)
    payload = {
      id: post.id,
      link: link,
      link_label: link_label,
      qr: qr_modules(link),
      accent: palette[:accent],
      accent_deep: palette[:accent_2],
      author: author_json(post_author),
      title: post.display_title.to_s,
      text: clip(plain_text(post.content), TEXT_LIMIT),
      truncated: plain_text(post.content).length > TEXT_LIMIT,
      image: image_json,
      counts: {
        likes: post.likes_count.to_i,
        comments: post.comments_count.to_i,
        reshares: post.reshares_count.to_i,
        seeds: seeds
      },
      date: (post.published_at || post.created_at).strftime("%b %-d, %Y"),
      label: label,
      series: series_line,
      share_text: share_text
    }
    if thread
      candidates = reply_candidates
      payload[:reply_candidates] = candidates.map { |c| reply_json(c) }
      payload[:replies] = chosen_replies(candidates, reply_ids).map { |c| reply_json(c) }
      payload[:can_choose_replies] = author_choosing?
    end
    payload
  end

  # Replies that may appear in a shared thread, best first.
  def reply_candidates
    scope = post.comments.active.moderation_visible.where(flagged: false)
                .where(user_id: eligible_repliers.select(:id))
    blocked = sharer ? sharer.blocked_user_ids : []
    scope = scope.where.not(user_id: blocked) if blocked.any?
    scope.includes(:rich_text_content, user: { profile: { avatar_attachment: :blob } })
         .order(likes_count: :desc, created_at: :asc)
         .limit(CANDIDATE_REPLIES * 3)
         .reject { |c| plain_text(c.content).blank? || plain_text(c.content).start_with?("[This comment has been deleted]") }
         .first(CANDIDATE_REPLIES)
  end

  private

  attr_reader :post, :sharer, :urls

  # The author picks which replies go in (from the safe candidates); anyone
  # else gets the most-liked ones.
  def chosen_replies(candidates, reply_ids)
    if author_choosing? && reply_ids.present?
      wanted = Array(reply_ids).map(&:to_i).uniq
      picked = wanted.filter_map { |id| candidates.find { |c| c.id == id } }
      return picked.first(MAX_REPLIES) if picked.any?
    end
    candidates.first(MAX_REPLIES)
  end

  def author_choosing? = sharer.present? && sharer.id == post.user_id

  def eligible_repliers
    User.active.joins(:profile).merge(Profile.adults_or_unknown)
        .where.not(id: UserRiskProfile.where(risk_level: UserRiskProfile.risk_levels[:restricted]..).select(:user_id))
  end

  def reply_json(comment)
    masked = post.anonymous? && comment.user_id == post.user_id
    {
      id: comment.id,
      author: author_json(masked ? nil : comment.user, op: comment.user_id == post.user_id),
      text: clip(plain_text(comment.content), REPLY_TEXT_LIMIT),
      truncated: plain_text(comment.content).length > REPLY_TEXT_LIMIT,
      likes: comment.likes_count.to_i,
      replies: comment.replies_count.to_i,
      date: comment.created_at.strftime("%b %-d, %Y")
    }
  end

  def post_author = post.anonymous? ? nil : post.user

  def author_json(user, op: false)
    return Author.new(anonymous: true, name: op ? "Anonymous (author)" : "Anonymous", username: nil, initial: nil,
                      avatar_url: nil, verified: false, founder: false).to_h unless user

    Author.new(
      anonymous: false,
      name: user.display_name,
      username: user.username,
      initial: user.username.first.upcase,
      avatar_url: avatar_url(user),
      verified: user.verified_at.present?,
      founder: Seeds::FOUNDER_ROLES.include?(user.role)
    ).to_h
  end

  # A small copy where the image host can make one (Cloudinary); the original
  # through our own domain otherwise, and as the fallback if the small copy
  # can't be drawn (the canvas needs CORS).
  def avatar_url(user)
    avatar = user.profile&.avatar
    return unless avatar&.attached?

    resized = urls.helpers.avatar_src(user.profile, 200)
    { url: resized.is_a?(String) ? resized : nil, fallback: urls.rails_storage_proxy_path(avatar) }
  rescue StandardError
    nil
  end

  def image_json
    return unless post.has_images?

    image = post.images.first
    {
      url: urls.helpers.photo_src(image, width: 1080).then { |src| src.is_a?(String) ? src : nil },
      fallback: urls.rails_storage_proxy_path(image)
    }
  rescue StandardError
    nil
  end

  # The accent of whoever wrote it; an anonymous breath wears the house colour
  # so the colour can't hint at who wrote it.
  def palette
    @palette ||= AccentPalette.for(post.anonymous? ? nil : post.user&.accent_color)
  end

  def seeds
    return 0 if post.anonymous?

    SeedEvent.where(post_id: post.id, user_id: post.user_id).sum(:points).to_i
  rescue StandardError
    0
  end

  def label
    return "Answered prayer" if post.prayer_status_prayer_answered?
    return "Prayer request" if post.prayer_status_prayer_pending?

    nil
  end

  # "Part 3 of 6 · Series name", counted among the parts everyone may see
  # (SeriesHelper#series_place). Anonymous breaths are never in a series.
  def series_line
    return if post.anonymous? || post.series.nil?

    place = urls.helpers.series_place(post)
    place && "Part #{place.first} of #{place.last} · #{post.series.title}"
  rescue StandardError
    nil
  end

  def ref = ShareReferral.ref_for(sharer, post)

  def code = post.id.to_s(36)

  def link
    @link ||= urls.short_post_url(code: code, ref: ref)
  end

  def link_label
    host = urls.request.host.to_s.delete_prefix("www.")
    [ host, "b", code, ref ].compact.join("/")
  end

  def share_text
    headline = post.display_title.presence || clip(plain_text(post.content), 90)
    "#{headline} #{link}".strip
  end

  def qr_modules(value) = self.class.qr_modules(value)

  def plain_text(rich)
    rich&.to_plain_text.to_s.gsub(/\r\n?/, "\n").gsub(/[ \t]+\n/, "\n").gsub(/\n{3,}/, "\n\n").strip
  end

  def clip(text, limit)
    return text if text.length <= limit

    cut = text[0, limit]
    cut = cut[0, cut.rindex(/\s/) || limit]
    "#{cut.rstrip}…"
  end
end

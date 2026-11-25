# frozen_string_literal: true

class Post < ApplicationRecord
  extend FriendlyId
  include Mentionable
  include AttachmentValidatable
  include SearchIndexable

  friendly_id :slug_source, use: :slugged

  # Rich text content
  has_rich_text :content

  # Multiple images (up to 5)
  has_many_attached :images

  # Optional voice note (max ~90s). Duration is stored client-side at
  # upload so the player can show total time before the audio loads.
  has_one_attached :voice_note

  # The generated link-preview image for breaths without a photo (PostOgCard).
  has_one_attached :og_card

  VOICE_MAX_MS    = 90_000
  VOICE_MAX_BYTES = 6.megabytes
  IMAGE_MAX_BYTES = 10.megabytes

  validate :voice_note_size_and_duration
  validate :images_content_type_and_size

  def images_content_type_and_size
    validate_image_attachment(:images, max_bytes: IMAGE_MAX_BYTES)
  end

  def has_voice_note?
    voice_note.attached?
  end

  def voice_duration_seconds
    return 0 if voice_duration_ms.blank?
    (voice_duration_ms.to_i / 1000.0).round
  end

  # Enums
  # validate: an unknown value from a form is a validation error (422), not an ArgumentError (500).
  enum :status, { draft: 0, published: 1, archived: 2, scheduled: 3 }, validate: true
  enum :kind,   { breath: 0, thread: 1 }, prefix: :kind, validate: true
  enum :prayer_status, { not_a_prayer: 0, prayer_pending: 1, prayer_answered: 2 }, prefix: :prayer_status, validate: true
  enum :moderation_status, { approved: 0, pending_review: 1, blocked: 2 }, prefix: :moderation

  has_many :prayer_intercessions, dependent: :destroy
  has_many :intercessors, through: :prayer_intercessions, source: :user

  scope :prayer_requests,   -> { where(prayer_status: %i[prayer_pending prayer_answered]) }
  scope :pending_prayers,   -> { where(prayer_status: :prayer_pending) }
  scope :answered_prayers,  -> { where(prayer_status: :prayer_answered) }

  def prayer?
    prayer_status_prayer_pending? || prayer_status_prayer_answered?
  end

  scope :threads_or_active, -> { where(kind: :thread).or(where("comments_count > 0")) }

  # A post is "threaded" if the author chose Thread mode OR if any reply
  # has shown up. Either way the card swaps to Open-thread chrome.
  def threaded?
    kind_thread? || comments_count.to_i > 0
  end

  def quote_repost?
    quoted_post_id.present?
  end

  # Associations
  belongs_to :user
  belongs_to :room, counter_cache: :posts_count, optional: true
  # A multi-part series by the same author (see Series). At most one.
  belongs_to :series, optional: true, inverse_of: :posts
  # Written as a page (Page): shown as the page, while user_id keeps the
  # member who wrote it for moderation and audit.
  belongs_to :page, optional: true
  has_many :scripture_citations, dependent: :delete_all
  has_many :comments, dependent: :destroy
  has_many :likes, as: :likeable, dependent: :destroy
  # Per-emoji counts for the card's reaction summary: rows of
  # (likeable_id, reaction_emoji, tally). Preloaded by CARD_INCLUDES in one
  # GROUP BY for every card on the page. Legacy likes with no emoji don't show.
  has_many :reaction_tallies, -> {
    where.not(reaction_emoji: [ nil, "" ])
      .group(:likeable_type, :likeable_id, :reaction_emoji)
      .select(:likeable_type, :likeable_id, :reaction_emoji, "COUNT(*) AS tally", "MIN(likes.id) AS first_like_id")
      .unscope(:order)
  }, as: :likeable, class_name: "Like"
  # The signed-in viewer's reaction (Current.user). One query per page when
  # preloaded; nil when nobody is signed in.
  has_one :viewer_like, -> { where(user_id: Current.user&.id) }, as: :likeable, class_name: "Like"
  has_many :bookmarks, dependent: :destroy
  has_many :reshares, dependent: :destroy
  has_many :reshared_by_users, through: :reshares, source: :user
  has_many :post_tags, dependent: :destroy
  has_many :tags, through: :post_tags
  has_many :reports, as: :reportable, dependent: :destroy
  has_many :notifications, as: :notifiable, dependent: :destroy
  has_one  :ai_moderation_review, as: :reviewable, dependent: :destroy

  # Quote-repost: a post can quote another post (Twitter-style quote tweet).
  # When the original is deleted, FK on_delete: :nullify keeps the quoting
  # post around but drops the embed.
  belongs_to :quoted_post, class_name: "Post", optional: true
  has_many :quoting_posts, class_name: "Post", foreign_key: :quoted_post_id, dependent: :nullify

  validate :cannot_quote_self
  after_create  :bump_quoted_reshares_count, if: -> { quoted_post_id.present? }
  after_create  :notify_quoted_post_author,  if: -> { quoted_post_id.present? }
  after_destroy :drop_quoted_reshares_count, if: -> { quoted_post_id.present? }

  # Post linking (outbound = posts this links TO, inbound = posts that link TO this)
  has_many :outbound_links, class_name: "PostLink", foreign_key: :source_post_id, dependent: :destroy
  has_many :inbound_links, class_name: "PostLink", foreign_key: :target_post_id, dependent: :destroy
  has_many :linked_posts, through: :outbound_links, source: :target_post
  has_many :linking_posts, through: :inbound_links, source: :source_post

  # Validations — title is optional for breaths (Twitter-style quick breath)
  # but still required for threads, where the title acts as the prompt.
  validates :title, length: { maximum: 200 }
  validates :title, presence: true, length: { minimum: 5 }, if: :kind_thread?
  validates :content, presence: true
  validate :language_is_clean
  validates :slug, presence: true, uniqueness: true
  validate :max_images_count
  validate :series_belongs_to_author
  validate :page_post_allowed, if: -> { page_id.present? && (new_record? || will_save_change_to_page_id?) }
  validate :page_post_not_anonymous, if: -> { page_id.present? }
  before_save :place_in_series, if: :will_save_change_to_series_id?

  # Search vectors (`searchable`, `search_title`) are written by database
  # triggers (SiteSearch::Schema) and read by SiteSearch::PostSearch. Kept out
  # of SELECT * so feed queries don't carry them around.
  self.ignored_columns += %w[searchable search_title]

  # Everything `posts/_card` touches, so a page of cards is a fixed number of
  # queries instead of ~10 per post (author + avatar blob, images, voice note,
  # tags, likes, moderation review, quoted post).
  CARD_INCLUDES = [
    :room, :tags, :rich_text_content, :ai_moderation_review, :voice_note_attachment,
    { images_attachments: :blob },
    { user: { profile: { avatar_attachment: :blob } } },
    :viewer_like, :reaction_tallies,
    { quoted_post: [ :user, { page: { logo_attachment: :blob } } ] }, :series,
    { page: { logo_attachment: :blob } }
  ].freeze
  scope :for_cards, -> { includes(*CARD_INCLUDES) }

  # Scopes
  scope :published_status, -> { where(status: :published).where(published_at: ..Time.current) }
  scope :moderation_visible, -> { where(moderation_status: :approved) }
  scope :scheduled_due,    -> { where(status: :scheduled).where(scheduled_for: ..Time.current) }
  scope :upcoming_for,     ->(user) { where(user: user, status: :scheduled).order(:scheduled_for) }
  # Public "published" feed — must be both published-status AND moderation-approved.
  # Held / blocked posts deliberately stay out of feeds; authors and admins reach
  # them via direct links (see Post#visible_to?).
  scope :published, -> { published_status.moderation_visible.without_suspended_pages }
  # A suspended page's posts leave every feed with it.
  scope :without_suspended_pages, -> {
    where("posts.page_id IS NULL OR posts.page_id NOT IN (SELECT pages.id FROM pages WHERE pages.status = 1)")
  }
  # Posts in the member's own name (not written as a page they run).
  scope :personal, -> { where(page_id: nil) }
  scope :as_page, -> { where.not(page_id: nil) }
  scope :drafts, -> { where(status: :draft) }
  # Breaths that carry their author's name (anonymous ones never count toward
  # or appear on the author's public profile).
  scope :named, -> { where(anonymous: false) }
  scope :featured, -> { where(featured: true) }
  # Breaths a public scripture page may quote: live, approved, signed with
  # the author's name, not a prayer request, and not in a private room or a
  # prayer/struggles room.
  scope :scripture_discussable, -> {
    published.named.where(prayer_status: :not_a_prayer)
             .where(user_id: User.where(active: true).select(:id))
             .where("posts.room_id IS NULL OR posts.room_id IN (?)",
                    Room.public_rooms.where.not(room_type: %i[prayers struggles]).select(:id))
  }
  # Parts a public series view may list: live, approved, signed with the
  # author's name, not a prayer request, and not in a private room. The same
  # bar the sitemap and scripture pages use for breaths shown to everyone.
  scope :series_listable, -> {
    published.named.where(prayer_status: :not_a_prayer)
             .where("posts.room_id IS NULL OR posts.room_id IN (?)", Room.public_rooms.select(:id))
  }
  scope :recent, -> { order(published_at: :desc) }
  scope :popular, -> { order(views_count: :desc) }
  scope :trending, -> { published.where(published_at: 7.days.ago..).order(engagement_score: :desc) }
  scope :by_room, ->(room) { where(room: room) }
  scope :by_user, ->(user) { where(user: user) }

  # Callbacks
  before_save :set_published_at, if: -> { status_changed? && published? }
  after_save :process_mentions_after_save
  after_commit :enqueue_ai_moderation_review, on: :create, if: -> { published? && moderation_approved? }
  after_update_commit :enqueue_ai_moderation_review_on_publish
  # Moderation looks at what was published; an edit to the words or photos of a
  # live breath gets looked at again (see AiModerationGateJob recheck).
  before_update :note_edit_for_moderation
  after_update_commit :recheck_moderation_after_edit
  after_commit :fanout_to_followers, on: :create, if: -> { published? && moderation_approved? }
  # "@gracechapel" in a post: the page's managers hear about it (once).
  after_commit :notify_mentioned_pages, on: :create, if: -> { published? }
  after_update_commit :fanout_to_followers_on_publish
  after_commit :bump_author_streak, on: :create, if: -> { published? && moderation_approved? }
  after_update_commit :bump_author_streak_on_publish

  # Live "new breaths" pill on the public feed. Drops a hidden marker into
  # #feed_incoming for anyone subscribed; a Stimulus controller counts the
  # markers and shows the pill. Fires on initial publish, on moderator
  # release, and when a draft or scheduled post goes live. (The scheduled
  # publisher writes with update_columns, so it calls
  # deliver_after_moderation_release! itself.)
  # One registration on purpose: Rails keeps only the last after_*_commit
  # for a given method name, so a separate on-create one was silently dropped.
  after_commit :broadcast_to_public_feed, on: %i[create update], if: :went_live_on_feed?

  after_create_commit -> { BadgeCheckJob.perform_later(user_id) }, if: -> { user_id.present? }
  after_destroy_commit :revoke_seeds_after_destroy
  # Followers of its series hear about a part once it's public (see SeriesPartAlertJob).
  after_commit :queue_series_part_alert, on: %i[create update]
  # Index the Bible references this breath quotes (scripture pages list them).
  after_commit :sync_scripture_citations, on: %i[create update]

  # Instance methods
  def engagement_score
    likes_count * 2 + comments_count * 3 + views_count * 0.1
  end

  def increment_views!
    increment!(:views_count)
  end

  VIEW_WINDOW = 1.hour

  # Counts a view at most once per viewer per hour, so refreshes and
  # back-and-forth don't rewrite the post row on every page load.
  # `viewer_key` is a user id or a hashed IP. Returns true when counted.
  def record_view!(viewer_key)
    key = "post_view/#{id}/#{viewer_key}"
    return false unless Rails.cache.write(key, true, expires_in: VIEW_WINDOW, unless_exist: true)

    increment_views!
    true
  end

  def author_name
    return "Anonymous" if anonymous?

    page_post? ? page.name : user.display_name
  end

  # Written as a page (and shown as it).
  def page_post? = page_id.present? && page.present?

  def reading_time
    word_count = content.to_plain_text.split.size
    minutes = (word_count / 200.0).ceil
    minutes < 1 ? 1 : minutes
  end

  def tag_list
    tags.pluck(:name).join(", ")
  end

  def tag_list=(names)
    self.tags = Tag.find_or_create_by_names(names.split(",").map(&:strip))
  end

  def cover_image
    images.first
  end

  # Shareable game results — a "game card" a post can carry. Whitelist of
  # games and their display metadata; slugs double as /games/<slug> paths.
  GAME_SHARES = {
    "quiz"               => { name: "Bible Quiz",         emoji: "📖" },
    "character_match"    => { name: "Character Match",    emoji: "👤" },
    "reference_scramble" => { name: "Reference Scramble", emoji: "🔀" },
    "history"            => { name: "Church History",     emoji: "⛪" },
    "pic_word"           => { name: "4 Pics 1 Word",      emoji: "🖼️" },
    "verse_memory"       => { name: "Verse Memory",       emoji: "🧠" }
  }.freeze

  # Never trust client-supplied share data: slug must be a known game and
  # every number is clamped. Returns a clean hash or nil.
  def self.sanitize_game_share(raw)
    data = raw.is_a?(Hash) ? raw : JSON.parse(raw.to_s)
    slug = data["slug"].to_s
    return nil unless GAME_SHARES.key?(slug)

    total = data["total"].to_i.clamp(1, 50)
    {
      "slug"   => slug,
      "score"  => data["score"].to_i.clamp(0, total),
      "total"  => total,
      "streak" => data["streak"].to_i.clamp(0, 50),
      "secs"   => data["secs"].to_i.clamp(0, 3600)
    }
  rescue JSON::ParserError
    nil
  end

  def game_share_info
    game_share.present? ? GAME_SHARES[game_share["slug"]] : nil
  end

  # FriendlyId source: prefer the explicit title, otherwise fall back to the
  # first chunk of the breath body so untitled breaths still get a slug.
  def slug_source
    return title if title.present?
    text = content&.to_plain_text.to_s.strip
    return "breath-#{Time.current.to_i}" if text.blank?
    text.first(60)
  end

  # Display title for the card heading: real title if present, otherwise nil
  # so the card hides the heading and just shows the body.
  def display_title
    title.presence
  end

  # Fine to list on a public series page or count in "Part 2 of 3".
  def series_listable?
    feed_visible? && !anonymous? && !prayer? && (room_id.nil? || room&.is_public?)
  end

  def has_images?
    images.attached? && images.any?
  end

  def feed_visible?
    published? && published_at.present? && published_at <= Time.current && moderation_approved? && !page&.suspended?
  end

  # Applied by AiModerationGateJob once the async gate has classified a freshly
  # created post (which is saved as :pending_review so it never reaches the feed
  # unmoderated). Writes the moderation columns without re-running validations or
  # the create callbacks, then fires the "released to the feed" side effects when
  # the post becomes publicly visible. Idempotent — safe to re-run.
  def apply_moderation_decision!(decision, reason: nil)
    target = case decision.to_sym
    when :block then "blocked"
    when :hold  then "pending_review"
    else             "approved"
    end
    return false if moderation_status == target

    update_columns(
      moderation_status: self.class.moderation_statuses.fetch(target),
      moderation_blocked_reason: reason,
      updated_at: Time.current
    )
    self.moderation_status = target # keep the in-memory record consistent
    Seeds.revoke_post(self) unless target == "approved" # held or blocked breaths earn nothing

    deliver_after_moderation_release! if feed_visible?
    true
  end

  # Fire-once delivery for a post that just became publicly visible: notify
  # followers, count the streak, and drop the live "new breaths" feed marker.
  def deliver_after_moderation_release!
    BreathFanoutJob.perform_later(id)
    SeriesPartAlertJob.set(wait: SeriesPartAlertJob::DELAY).perform_later(id) if series_id
    bump_author_streak
    broadcast_to_public_feed
    queue_for_search_engines(force: true)
  end

  def held_for_review?
    moderation_pending_review? || moderation_blocked? || legacy_held_for_review?
  end

  def visible_to?(viewer)
    return false unless readable_by?(viewer)
    return true unless held_for_review?

    author_or_staff?(viewer)
  end

  # Live = published status with a publish time that has arrived. Drafts,
  # scheduled breaths and archived ones are not live.
  def live?
    published? && (published_at.nil? || published_at <= Time.current)
  end

  # Drafts / scheduled / archived breaths exist only for their author and
  # staff. Everyone else (signed-out included) must get a 404 — never a page
  # that confirms the breath exists.
  def readable_by?(viewer)
    live? || author_or_staff?(viewer)
  end

  def author_or_staff?(viewer)
    return false unless viewer

    viewer == user ||
      (viewer.respond_to?(:admin?) && (viewer.admin? || viewer.super_admin?)) ||
      (viewer.respond_to?(:moderator?) && viewer.moderator?)
  end

  # Pre-existing logic kept as a fallback for older records that have an
  # AiModerationReview but no moderation_status set yet.
  def legacy_held_for_review?
    review = ai_moderation_review
    return false unless review
    return false unless review.severity == "high"

    !%w[dismissed cleared].include?(review.status)
  end

  # Search engines (IndexNow) hear about a breath only while it's a public,
  # named, non-prayer page: live, approved, and outside private rooms.
  def search_indexable?
    feed_visible? && !anonymous? && !prayer? && (room_id.nil? || room&.is_public?)
  end

  def search_index_urls
    [ search_url_helpers.post_url(self) ]
  end

  def self.search_index_candidates(since)
    published.named.where(updated_at: since..).includes(:room)
  end

  private

  def set_published_at
    self.published_at ||= Time.current
  end

  def max_images_count
    if images.attached? && images.count > 5
      errors.add(:images, "cannot exceed 5 images per post")
    end
  end

  # Only the author's own series, and never for an anonymous breath (the
  # series page carries the author's name).
  def series_belongs_to_author
    return if series_id.blank?

    if series.nil? || series.user_id != user_id
      errors.add(:series, "must be one of your own")
    elsif anonymous?
      errors.add(:base, "An anonymous breath can't be part of a series (the series shows your name)")
    end
  end

  # A breath joining a series goes to the end (or takes the part number in
  # its title) unless a place was given.
  def place_in_series
    return self.series_position = nil if series_id.blank?
    return if series_position.present? && will_save_change_to_series_position?

    self.series_position = series.next_position(title: SeriesTitle.effective_title(self))
  end

  def page_post_allowed
    if page.nil? || !page.active?
      errors.add(:page, "isn't available")
    elsif !page.editor?(user)
      errors.add(:base, "You can only post as a page you help run")
    end
  end

  def page_post_not_anonymous
    errors.add(:base, "A page can't post anonymously") if anonymous?
  end

  def notify_mentioned_pages
    handles = extract_mentions.map(&:downcase).uniq.first(10) - %w[everyone all here]
    return if handles.empty?

    taken = User.where("lower(username) IN (?)", handles).pluck(Arel.sql("lower(username)"))
    Page.listed.where("lower(handle) IN (?)", handles - taken).where.not(id: page_id).find_each do |mentioned|
      mentioned.managers.where.not(id: user_id).find_each do |manager|
        Notification.create(user: manager, notifiable: self, notification_type: :page_mentioned)
      end
    end
  rescue StandardError => e
    Rails.logger.warn("[page-mentions] failed for post #{id}: #{e.class}: #{e.message}")
  end

  def cannot_quote_self
    return unless quoted_post_id.present? && quoted_post_id == id
    errors.add(:quoted_post_id, "can't be itself")
  end

  def bump_quoted_reshares_count
    Post.where(id: quoted_post_id).update_all("reshares_count = COALESCE(reshares_count, 0) + 1")
  end

  def drop_quoted_reshares_count
    Post.where(id: quoted_post_id)
        .where("reshares_count > 0")
        .update_all("reshares_count = reshares_count - 1")
  end

  def notify_quoted_post_author
    target = quoted_post
    return unless target
    return if target.user_id == user_id

    notification = Notification.create(
      user: target.user,
      actor: (page_id ? nil : user), # a page's quote speaks as the page
      notifiable: self,
      notification_type: :post_reshared
    )
    return if notification.persisted?

    Rails.logger.warn(
      "[quote-notification] not created for post #{id}: #{notification.errors.full_messages.join(', ')}"
    )
  rescue StandardError => e
    Rails.logger.warn "[quote-notification] failed for post #{id}: #{e.message}"
  end

  def voice_note_size_and_duration
    return unless voice_note.attached?

    if voice_note.blob.byte_size > VOICE_MAX_BYTES
      errors.add(:voice_note, "is too large (max #{VOICE_MAX_BYTES / 1.megabyte}MB)")
    end
    if voice_duration_ms.present? && voice_duration_ms.to_i > VOICE_MAX_MS
      errors.add(:voice_note, "must be 1 minute 30 seconds or shorter")
    end
  end

  def process_mentions_after_save
    process_mentions!(user) if user.present?
  end

  def enqueue_ai_moderation_review
    # The gate job classifies AND enforces (retro-hold/block + review row +
    # risk scoring) — the breath is already live, this runs behind it.
    # Proven authors skip the AI call entirely.
    if user&.trusted_breather?
      record_trusted_moderation_skip
    else
      AiModerationGateJob.perform_later(id)
    end
  end

  # A settled review row must still be written for trusted skips —
  # ModerationBacklogSweepJob treats review-less published posts as lost
  # jobs and would re-enqueue the AI gate for them forever.
  def record_trusted_moderation_skip
    AiModerationReview.from_result(
      reviewable: self,
      user: user,
      result: Ai::Moderation::Result.trusted_skip
    )
  rescue StandardError => e
    # Fail open: with no row the sweep re-enqueues the normal gate job —
    # the post just costs one AI call instead of zero.
    Rails.logger.error("[TrustGate] review row failed for post #{id}: #{e.class}: #{e.message}")
  end

  def note_edit_for_moderation
    @edited_for_moderation = will_save_change_to_title? ||
                             attachment_changes.key?("images") || attachment_changes.key?("voice_note") ||
                             rich_text_content&.changed?
  end

  def recheck_moderation_after_edit
    edited = @edited_for_moderation
    @edited_for_moderation = false
    return unless edited && published?
    return if saved_change_to_status? # just published: the first review covers it

    AiModerationGateJob.perform_later(id, recheck: true)
  end

  def enqueue_ai_moderation_review_on_publish
    return unless saved_change_to_status? && published? && moderation_approved?

    enqueue_ai_moderation_review
  end

  def fanout_to_followers
    BreathFanoutJob.perform_later(id)
  end

  def went_live_on_feed?
    return false unless feed_visible?

    previously_new_record? || saved_change_to_moderation_status? || saved_change_to_status?
  end

  def broadcast_to_public_feed
    Turbo::StreamsChannel.broadcast_prepend_to(
      "feed:public",
      target: "feed_incoming",
      html: %(<div data-post-arrival="#{id}" hidden></div>).html_safe
    )
  rescue StandardError => e
    Rails.logger.warn "[feed-pill] broadcast failed for post #{id}: #{e.message}"
  end

  def fanout_to_followers_on_publish
    return unless saved_change_to_status? && published? && moderation_approved?

    fanout_to_followers
  end

  def bump_author_streak
    bumped = user&.bump_breath_streak!
    Seeds.breath_published(self, streak_bumped: bumped.present?)
  end

  # Deleted: the author loses the seeds this breath earned them.
  def revoke_seeds_after_destroy
    Seeds.revoke_post(id, author_id: user_id)
  end

  def bump_author_streak_on_publish
    return unless saved_change_to_status? && published? && moderation_approved?

    bump_author_streak
  end

  private

  # No offensive language in the title or text (instant, before saving; the AI gate still reviews).
  def language_is_clean
    text = [ title, content&.to_plain_text ].compact.join(" ")
    errors.add(:base, CleanLanguage::MESSAGE) if CleanLanguage.offensive?(text)
  end

  def queue_series_part_alert
    return unless series_id && series_listable?
    return unless previously_new_record? || saved_change_to_series_id? || saved_change_to_status? ||
                  saved_change_to_moderation_status?

    SeriesPartAlertJob.set(wait: SeriesPartAlertJob::DELAY).perform_later(id)
  end

  def sync_scripture_citations
    ScriptureCitation.sync(self)
  end
end

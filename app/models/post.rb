# frozen_string_literal: true

class Post < ApplicationRecord
  extend FriendlyId
  include PgSearch::Model
  include Mentionable
  include AttachmentValidatable

  friendly_id :slug_source, use: :slugged

  # Rich text content
  has_rich_text :content

  # Multiple images (up to 5)
  has_many_attached :images

  # Optional voice note (max ~90s). Duration is stored client-side at
  # upload so the player can show total time before the audio loads.
  has_one_attached :voice_note

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
  enum :status, { draft: 0, published: 1, archived: 2, scheduled: 3 }
  enum :kind,   { breath: 0, thread: 1 }, prefix: :kind
  enum :prayer_status, { not_a_prayer: 0, prayer_pending: 1, prayer_answered: 2 }, prefix: :prayer_status
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
  has_many :comments, dependent: :destroy
  has_many :likes, as: :likeable, dependent: :destroy
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
  validates :slug, presence: true, uniqueness: true
  validate :max_images_count

  # Search
  pg_search_scope :search,
                  against: [ :title ],
                  associated_against: {
                    rich_text_content: [ :body ]
                  },
                  using: {
                    tsearch: { prefix: true, dictionary: "english" }
                  }

  # Scopes
  scope :published_status, -> { where(status: :published).where("published_at <= ?", Time.current) }
  scope :moderation_visible, -> { where(moderation_status: :approved) }
  scope :scheduled_due,    -> { where(status: :scheduled).where("scheduled_for <= ?", Time.current) }
  scope :upcoming_for,     ->(user) { where(user: user, status: :scheduled).order(:scheduled_for) }
  # Public "published" feed — must be both published-status AND moderation-approved.
  # Held / blocked posts deliberately stay out of feeds; authors and admins reach
  # them via direct links (see Post#visible_to?).
  scope :published, -> { published_status.moderation_visible }
  scope :drafts, -> { where(status: :draft) }
  scope :featured, -> { where(featured: true) }
  scope :recent, -> { order(published_at: :desc) }
  scope :popular, -> { order(views_count: :desc) }
  scope :trending, -> { published.where("published_at > ?", 7.days.ago).order(engagement_score: :desc) }
  scope :by_room, ->(room) { where(room: room) }
  scope :by_user, ->(user) { where(user: user) }

  # Callbacks
  before_save :set_published_at, if: -> { status_changed? && published? }
  after_save :process_mentions_after_save
  after_commit :enqueue_ai_moderation_review, on: :create, if: -> { published? && moderation_approved? }
  after_update_commit :enqueue_ai_moderation_review_on_publish
  after_commit :fanout_to_followers, on: :create, if: -> { published? && moderation_approved? }
  after_update_commit :fanout_to_followers_on_publish
  after_commit :bump_author_streak, on: :create, if: -> { published? && moderation_approved? }
  after_update_commit :bump_author_streak_on_publish

  # Live "new breaths" pill on the public feed. Drops a hidden marker into
  # #feed_incoming for anyone subscribed; a Stimulus controller counts the
  # markers and shows the pill. Fires on initial publish and on moderator
  # release.
  after_commit :broadcast_to_public_feed, on: :create, if: :feed_visible?
  after_update_commit :broadcast_to_public_feed,
                      if: -> { saved_change_to_moderation_status? && feed_visible? }

  # Instance methods
  def engagement_score
    likes_count * 2 + comments_count * 3 + views_count * 0.1
  end

  def increment_views!
    increment!(:views_count)
  end

  def author_name
    anonymous? ? "Anonymous" : user.display_name
  end

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

  def has_images?
    images.attached? && images.any?
  end

  def feed_visible?
    published? && published_at.present? && published_at <= Time.current && moderation_approved?
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

    deliver_after_moderation_release! if feed_visible?
    true
  end

  # Fire-once delivery for a post that just became publicly visible: notify
  # followers, count the streak, and drop the live "new breaths" feed marker.
  def deliver_after_moderation_release!
    BreathFanoutJob.perform_later(id)
    bump_author_streak
    broadcast_to_public_feed
  end

  def held_for_review?
    moderation_pending_review? || moderation_blocked? || legacy_held_for_review?
  end

  def visible_to?(viewer)
    return true unless held_for_review?
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

  private

  def set_published_at
    self.published_at ||= Time.current
  end

  def max_images_count
    if images.attached? && images.count > 5
      errors.add(:images, "cannot exceed 5 images per post")
    end
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
      actor: user,
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
    AiModerationGateJob.perform_later(id)
  end

  def enqueue_ai_moderation_review_on_publish
    return unless saved_change_to_status? && published? && moderation_approved?

    enqueue_ai_moderation_review
  end

  def fanout_to_followers
    BreathFanoutJob.perform_later(id)
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
    user&.bump_breath_streak!
  end

  def bump_author_streak_on_publish
    return unless saved_change_to_status? && published? && moderation_approved?

    bump_author_streak
  end
end

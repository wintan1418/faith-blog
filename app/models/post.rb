# frozen_string_literal: true

class Post < ApplicationRecord
  extend FriendlyId
  include PgSearch::Model
  include Mentionable

  friendly_id :slug_source, use: :slugged

  # Rich text content
  has_rich_text :content

  # Multiple images (up to 5)
  has_many_attached :images

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

  def process_mentions_after_save
    process_mentions!(user) if user.present?
  end

  def enqueue_ai_moderation_review
    AiModerationReviewJob.perform_later(self)
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

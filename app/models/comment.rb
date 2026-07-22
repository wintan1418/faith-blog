# frozen_string_literal: true

class Comment < ApplicationRecord
  include Mentionable

  # Rich text content
  has_rich_text :content

  # Associations
  belongs_to :user
  belongs_to :post, counter_cache: true
  belongs_to :parent_comment, class_name: "Comment", optional: true, counter_cache: :replies_count
  has_many :replies, class_name: "Comment", foreign_key: :parent_comment_id, dependent: :destroy
  has_many :likes, as: :likeable, dependent: :destroy
  has_many :reports, as: :reportable, dependent: :destroy
  has_many :notifications, as: :notifiable, dependent: :destroy
  after_create_commit -> { BadgeCheckJob.perform_later(user_id) }, if: -> { user_id.present? }
  has_one  :ai_moderation_review, as: :reviewable, dependent: :destroy

  # Enums
  enum :moderation_status, { approved: 0, pending_review: 1, blocked: 2 }, prefix: :moderation

  # Validations
  validates :content, presence: true
  validate :parent_comment_belongs_to_same_post

  # Callbacks
  before_validation :unwrap_leaked_trix_html
  after_save :process_mentions_after_save
  after_commit :enqueue_ai_moderation_review, on: :create, if: :moderation_approved?

  # Scopes
  scope :root_comments, -> { where(parent_comment_id: nil) }
  scope :active, -> { where(deleted_at: nil) }
  scope :moderation_visible, -> { where(moderation_status: :approved) }
  scope :flagged, -> { where(flagged: true) }
  scope :recent, -> { order(created_at: :desc) }
  scope :oldest_first, -> { order(created_at: :asc) }

  # Comments that the given viewer is allowed to see: approved ones for
  # everyone, plus a viewer's own held/blocked comments, plus everything for
  # staff. Mirrors #visible_to? but as a query so list views don't leak
  # pending_review/blocked comments to the whole world.
  def self.visible_for(viewer)
    return moderation_visible unless viewer
    return all if viewer.respond_to?(:moderator?) &&
                  (viewer.moderator? || viewer.admin? || viewer.super_admin?)

    moderation_visible.or(where(user_id: viewer.id))
  end

  # Instance methods
  def soft_delete!
    return if deleted?

    transaction do
      update!(deleted_at: Time.current)
      # Soft-delete bypasses counter_cache (it only fires on destroy), so the
      # post's comments_count and parent's replies_count would drift high as
      # deleted comments accumulate. Keep them in sync with the .active scope
      # used for display.
      Post.where(id: post_id).update_all("comments_count = GREATEST(comments_count - 1, 0)")
      if parent_comment_id
        Comment.where(id: parent_comment_id).update_all("replies_count = GREATEST(replies_count - 1, 0)")
      end
    end
    content.update(body: "[This comment has been deleted]") if content.present?
  end

  def deleted?
    deleted_at.present?
  end

  def edited?
    edited_at.present?
  end

  def mark_as_edited!
    update(edited_at: Time.current)
  end

  def depth
    parent_comment_id.nil? ? 0 : parent_comment.depth + 1
  end

  def root_comment?
    parent_comment_id.nil?
  end

  def reply?
    parent_comment_id.present?
  end

  def held_for_review?
    moderation_pending_review? || moderation_blocked?
  end

  def visible_to?(viewer)
    return true unless held_for_review?
    return false unless viewer
    return true if viewer == user
    return true if viewer.respond_to?(:admin?) && (viewer.admin? || viewer.super_admin?)
    return true if viewer.respond_to?(:moderator?) && viewer.moderator?
    false
  end

  private

  # A reply must hang off a comment on the same post. Without this a crafted
  # request could thread a reply under a comment from a different post and
  # corrupt the tree the UI renders.
  def parent_comment_belongs_to_same_post
    return if parent_comment_id.blank?
    return if parent_comment&.post_id == post_id

    errors.add(:parent_comment, "must belong to the same post")
  end

  # Defense-in-depth against the mobile-browser autofill bug: it would
  # refill a reply field with a previously submitted comment's raw Trix
  # markup, so the body arrived as the literal string
  # '<div class="trix-content">…</div>'. The client-side pristine-field
  # controller stops it at the source; this catches anything that still
  # slips through (or was already saved) and recovers the real text.
  def unwrap_leaked_trix_html
    return if content.blank?

    plain = content.to_plain_text.to_s
    return unless plain.include?("trix-content") && plain.match?(/<\s*\/?\s*(div|p|br|span)\b/i)

    recovered = ActionText::Content.new(CGI.unescapeHTML(plain)).to_plain_text.strip
    self.content = recovered if recovered.present?
  end

  def process_mentions_after_save
    process_mentions!(user) if user.present?
  end

  def enqueue_ai_moderation_review
    AiModerationReviewJob.perform_later(self)
  end
end

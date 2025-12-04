# frozen_string_literal: true

class Post < ApplicationRecord
  extend FriendlyId
  include PgSearch::Model

  friendly_id :title, use: :slugged

  # Rich text content
  has_rich_text :content

  # Enums
  enum :status, { draft: 0, published: 1, archived: 2 }

  # Associations
  belongs_to :user
  belongs_to :room, counter_cache: :posts_count
  has_many :comments, dependent: :destroy
  has_many :likes, as: :likeable, dependent: :destroy
  has_many :bookmarks, dependent: :destroy
  has_many :post_tags, dependent: :destroy
  has_many :tags, through: :post_tags
  has_many :reports, as: :reportable, dependent: :destroy
  has_many :notifications, as: :notifiable, dependent: :destroy

  # Validations
  validates :title, presence: true, length: { minimum: 5, maximum: 200 }
  validates :content, presence: true
  validates :slug, presence: true, uniqueness: true

  # Search
  pg_search_scope :search,
                  against: [:title],
                  associated_against: {
                    rich_text_content: [:body]
                  },
                  using: {
                    tsearch: { prefix: true, dictionary: "english" }
                  }

  # Scopes
  scope :published, -> { where(status: :published).where("published_at <= ?", Time.current) }
  scope :drafts, -> { where(status: :draft) }
  scope :featured, -> { where(featured: true) }
  scope :recent, -> { order(published_at: :desc) }
  scope :popular, -> { order(views_count: :desc) }
  scope :trending, -> { published.where("published_at > ?", 7.days.ago).order(engagement_score: :desc) }
  scope :by_room, ->(room) { where(room: room) }
  scope :by_user, ->(user) { where(user: user) }

  # Callbacks
  before_save :set_published_at, if: -> { status_changed? && published? }

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

  private

  def set_published_at
    self.published_at ||= Time.current
  end
end


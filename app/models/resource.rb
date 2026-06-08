# frozen_string_literal: true

class Resource < ApplicationRecord
  extend FriendlyId
  include PgSearch::Model

  friendly_id :title, use: :slugged

  # Enums
  enum :resource_type, { link: 0, video: 1, pdf: 2, audio: 3, book: 4 }

  # Associations
  belongs_to :user
  belongs_to :resource_category
  belongs_to :approved_by, class_name: "User", optional: true
  has_one_attached :file
  has_many :reports, as: :reportable, dependent: :destroy

  FILE_MAX_BYTES = 25.megabytes
  FILE_CONTENT_TYPES = %w[
    application/pdf
    audio/mpeg audio/mp3 audio/mp4 audio/aac audio/wav audio/ogg audio/webm audio/x-m4a
    image/jpeg image/png image/webp
  ].freeze

  # Validations
  validates :title, presence: true, length: { maximum: 200 }
  validates :description, length: { maximum: 1000 }
  validates :url, presence: true, if: -> { link? || video? }
  validates :file, presence: true, if: -> { pdf? || audio? }
  validates :slug, presence: true, uniqueness: true
  validate  :file_content_type_and_size

  def file_content_type_and_size
    return unless file.attached? && file.blob

    if file.blob.content_type.present? && FILE_CONTENT_TYPES.exclude?(file.blob.content_type)
      errors.add(:file, "must be a PDF, audio, or image file")
    end
    if file.blob.byte_size.to_i > FILE_MAX_BYTES
      errors.add(:file, "is too large (max #{FILE_MAX_BYTES / 1.megabyte}MB)")
    end
  end

  # Search
  pg_search_scope :search,
                  against: [ :title, :description ],
                  using: {
                    tsearch: { prefix: true, dictionary: "english" }
                  }

  # Scopes
  scope :approved, -> { where(approved: true) }
  scope :pending, -> { where(approved: false) }
  scope :featured, -> { where(featured: true) }
  scope :recent, -> { order(created_at: :desc) }
  scope :popular, -> { order(views_count: :desc) }
  scope :by_type, ->(type) { where(resource_type: type) }
  scope :by_category, ->(category) { where(resource_category: category) }

  # Instance methods
  def approve!(admin)
    update(approved: true, approved_by: admin, approved_at: Time.current)
  end

  def reject!(admin)
    update(approved: false, approved_by: admin, approved_at: Time.current)
  end

  def increment_views!
    increment!(:views_count)
  end

  def increment_downloads!
    increment!(:downloads_count)
  end

  def type_icon
    case resource_type.to_sym
    when :link then "externallink"
    when :video then "video"
    when :pdf then "filetext"
    when :audio then "headphones"
    when :book then "bookopen"
    else "filetext"
    end
  end
end

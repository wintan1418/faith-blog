# frozen_string_literal: true

# A piece of work on someone's Portfolio tab: photos, a write-up, the part
# they played, skills used, a link and an optional PDF (case study, deck...).
class PortfolioItem < ApplicationRecord
  include AttachmentValidatable

  MAX_IMAGES = 8
  IMAGE_MAX_BYTES = 10.megabytes
  PDF_MAX_BYTES = 10.megabytes
  MAX_SKILLS = 8
  MAX_ITEMS = 60

  CATEGORIES = {
    "Design" => "🎨", "Software & apps" => "💻", "Writing" => "✍️", "Photography" => "📷", "Video & film" => "🎬",
    "Music & audio" => "🎵", "Architecture & building" => "🏗️", "Engineering" => "⚙️", "Research" => "🔬",
    "Marketing & brand" => "📣", "Business & startups" => "🚀", "Events" => "🎪", "Teaching & training" => "🎓",
    "Health & care" => "🩺", "Fashion & beauty" => "👗", "Food" => "🍲", "Art & craft" => "🖌️",
    "Ministry & outreach" => "🕊️", "Community & charity" => "🤝", "Other" => "✨"
  }.freeze

  belongs_to :user
  has_many_attached :images
  has_one_attached :document

  validates :title, presence: true, length: { maximum: 100 }
  validates :summary, length: { maximum: 160 }
  validates :description, length: { maximum: 3000 }
  validates :contribution, length: { maximum: 80 }
  validates :category, inclusion: { in: CATEGORIES.keys }, allow_blank: true
  validates :link_url, length: { maximum: 500 },
                       format: { with: %r{\Ahttps://\S+\z}i, message: "must start with https://" }, allow_blank: true
  validate :images_are_valid
  validate :document_is_a_pdf
  validate :skills_are_short
  validate :not_too_many, on: :create

  normalizes :title, :summary, :contribution, with: ->(text) { text.to_s.squish.presence }

  before_create { self.position = (user.portfolio_items.maximum(:position) || -1) + 1 }

  scope :ordered, -> { order(:position, created_at: :desc) }
  scope :visible, -> { where(hidden_at: nil) }

  def hidden? = hidden_at.present?
  def emoji = CATEGORIES[category] || "✨"
  def cover = images.attachments.first

  def skills_list = skills.join(", ")

  def skills_list=(value)
    self.skills = value.to_s.split(",").map { |s| s.squish.first(40) }.compact_blank.uniq(&:downcase).first(MAX_SKILLS)
  end

  def completed_month = completed_on&.strftime("%Y-%m")

  def completed_month=(value)
    self.completed_on = Experience.month_to_date(value)
  end

  # "github.com/ada/app" for the link button.
  def link_label = link_url.to_s.sub(%r{\Ahttps://(www\.)?}i, "").chomp("/").first(40)

  # Moves the item one place up or down among its owner's items.
  def move!(direction)
    items = user.portfolio_items.to_a
    i = items.index(self)
    j = direction.to_s == "up" ? i.to_i - 1 : i.to_i + 1
    return if i.nil? || j.negative? || j >= items.size

    items[i], items[j] = items[j], items[i]
    transaction { items.each_with_index { |item, k| item.update_columns(position: k) } }
  end

  # New photos, PDF or words get the same AI look as posts (see PortfolioModerationJob).
  before_save { @needs_review = new_record? || will_save_change_to_title? || will_save_change_to_description? || attachment_changes.any? }
  after_commit :moderate, on: %i[create update], if: -> { @needs_review }

  private

  def moderate
    @needs_review = false
    Ai::Moderation::Client.stub? ? PortfolioModerationJob.perform_now(self) : PortfolioModerationJob.perform_later(self)
  end

  def images_are_valid
    errors.add(:images, "can be up to #{MAX_IMAGES} photos") if images.attachments.size > MAX_IMAGES
    validate_image_attachment(:images, max_bytes: IMAGE_MAX_BYTES)
  end

  def document_is_a_pdf
    return unless document.attached?

    blob = document.blob
    pdf = blob.content_type == "application/pdf" && File.extname(blob.filename.to_s).casecmp?(".pdf")
    errors.add(:document, "must be a PDF") unless pdf
    errors.add(:document, "is too large (max #{PDF_MAX_BYTES / 1.megabyte}MB)") if blob.byte_size.to_i > PDF_MAX_BYTES
  end

  def skills_are_short
    errors.add(:skills, "can have at most #{MAX_SKILLS}") if skills.size > MAX_SKILLS
  end

  def not_too_many
    errors.add(:base, "You can have up to #{MAX_ITEMS} pieces of work") if user && user.portfolio_items.count >= MAX_ITEMS
  end
end

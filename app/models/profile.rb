# frozen_string_literal: true

class Profile < ApplicationRecord
  include AttachmentValidatable

  AVATAR_MAX_BYTES = 10.megabytes

  # Associations
  belongs_to :user
  has_one_attached :avatar

  # Validations
  validates :bio, length: { maximum: 500 }
  validates :location, length: { maximum: 100 }
  validates :faith_background, length: { maximum: 200 }
  validates :website, length: { maximum: 255 }
  validate  :avatar_content_type_and_size

  def avatar_content_type_and_size
    validate_image_attachment(:avatar, max_bytes: AVATAR_MAX_BYTES)
  end

  # Professional headline and skills (LinkedIn-style). Skills come in as a comma list.
  MAX_SKILLS = 30
  validates :headline, length: { maximum: 120 }
  validate :skills_are_short

  def skills_list=(value)
    self.skills = value.to_s.split(",").map { |s| s.squish.first(40) }.compact_blank.uniq { |s| s.downcase }.first(MAX_SKILLS)
  end

  def skills_list = skills.join(", ")

  # Industries, close to LinkedIn's top-level list so imports map cleanly.
  INDUSTRIES = [
    "Accounting", "Administration", "Agriculture", "Architecture & Planning", "Arts & Design", "Aviation",
    "Banking", "Civil Engineering", "Construction", "Consulting", "Customer Service", "Education",
    "Energy, Oil & Gas", "Engineering", "Entertainment & Media", "Environmental Services", "Events",
    "Fashion & Beauty", "Financial Services", "Food & Beverage", "Government & Public Service",
    "Healthcare & Medicine", "Hospitality & Tourism", "Human Resources", "Information Technology",
    "Insurance", "Journalism & Publishing", "Law & Legal Services", "Logistics & Supply Chain",
    "Manufacturing", "Marketing & Advertising", "Military & Security", "Mining", "Ministry & Religious Institutions",
    "Music", "Non-profit & NGOs", "Pharmaceuticals", "Photography & Film", "Real Estate", "Research & Science",
    "Retail & E-commerce", "Sales", "Social Work & Counselling", "Software Development", "Sports & Fitness",
    "Student", "Telecommunications", "Transportation", "Writing & Editing", "Other"
  ].freeze
  validates :industry, length: { maximum: 80 }

  # Prefer the list's spelling when an import or a person's typing is close.
  def industry=(value)
    text = value.to_s.squish
    super(INDUSTRIES.find { |i| i.casecmp?(text) } || text.presence)
  end

  # "Open to": what the member is looking for. The first one they hold, in this
  # order, colours the ring on their photo.
  OPEN_TO = {
    "hiring"       => { label: "Hiring",            badge: "Hiring",        colour: "gold" },
    "work"         => { label: "New work",          badge: "Open to work",  colour: "blue" },
    "mentoring"    => { label: "Mentoring others",  badge: "Mentor",        colour: "green" },
    "freelance"    => { label: "Freelance work",    badge: "Freelance",     colour: "coral" },
    "volunteering" => { label: "Volunteering",      badge: "Volunteer",     colour: "violet" }
  }.freeze
  enum :open_to_visibility, { everyone: 0, connections: 1 }, prefix: :open_to_shown_to

  def open_to=(values)
    picked = Array(values).map(&:to_s)
    super(OPEN_TO.keys & picked)
  end

  # The digital business card's colour.
  CARD_STYLES = %w[mint midnight gold light].freeze
  validates :card_style, inclusion: { in: CARD_STYLES }

  def skills_are_short
    errors.add(:skills, "can have at most #{MAX_SKILLS}") if skills.size > MAX_SKILLS
  end

  # Birthdays: day and month are celebrated with brethren; the year is optional and never shown.
  # Dates are judged in West Africa time, where most of the community is.
  BIRTHDAY_ZONE = "Africa/Lagos"

  validates :birth_month, inclusion: { in: 1..12 }, allow_nil: true
  validates :birth_year, numericality: { only_integer: true, greater_than: 1900 }, allow_nil: true
  validate :birthday_is_a_real_date

  # Profiles whose birthday is `date` (Feb 29 birthdays are celebrated on Feb 28 in other years).
  scope :birthday_on, lambda { |date|
    scope = where(birth_month: date.month, birth_day: date.day)
    scope = scope.or(where(birth_month: 2, birth_day: 29)) if date.month == 2 && date.day == 28 && !date.leap?
    scope
  }

  def self.today_for_birthdays = Time.current.in_time_zone(BIRTHDAY_ZONE).to_date

  def birthday? = birth_month.present? && birth_day.present?

  def birthday_today?
    birthday? && Profile.where(id: id).birthday_on(Profile.today_for_birthdays).exists?
  end

  # "May 14"
  def birthday_label
    Date.new(2000, birth_month, birth_day).strftime("%B %-d") if birthday?
  end

  def birthday_is_a_real_date
    return if birth_month.blank? && birth_day.blank?
    return errors.add(:birth_day, "needs a month too") if birth_month.blank? || birth_day.blank?

    errors.add(:birth_day, "isn't a real date") unless Date.valid_date?(2000, birth_month.to_i, birth_day.to_i)
    errors.add(:birth_year, "can't be in the future") if birth_year.present? && birth_year > Date.current.year
  end

  # Public church / assembly (the Brethren Card one stays private), plus match keys.
  validates :assembly, length: { maximum: 120 }
  before_save do
    self.assembly = assembly.to_s.squish.presence
    self.assembly_key = MatchKey.for(assembly)
    self.city_key = MatchKey.city(location)
  end

  # Assemblies people already use, most common first (for pick-from-list as you type).
  def self.popular_assemblies(limit = 300)
    where.not(assembly_key: nil).group(:assembly_key).order(Arel.sql("COUNT(*) DESC"))
         .limit(limit).pluck(Arel.sql("MIN(assembly)"))
  end

  # New profile photos get an AI look (see AvatarModerationJob).
  before_save { @avatar_changed = attachment_changes.key?("avatar") }
  after_commit :moderate_avatar, if: -> { @avatar_changed && avatar.attached? }
  # The headline (professional profile) and photo are getting-started steps.
  before_save { @onboarding_changed = will_save_change_to_headline? || attachment_changes.key?("avatar") }
  after_commit -> { OnboardingChecklist.broadcast_refresh(user) }, if: -> { @onboarding_changed }

  def moderate_avatar
    @avatar_changed = false
    Ai::Moderation::Client.stub? ? AvatarModerationJob.perform_now(self) : AvatarModerationJob.perform_later(self)
  end

  # Avatar variant helpers
  def avatar_thumbnail
    avatar.variant(resize_to_fill: [ 100, 100 ])
  end

  def avatar_medium
    avatar.variant(resize_to_fill: [ 200, 200 ])
  end

  def avatar_large
    avatar.variant(resize_to_fill: [ 400, 400 ])
  end
end

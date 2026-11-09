# frozen_string_literal: true

# A language someone speaks, with LinkedIn's proficiency levels.
class UserLanguage < ApplicationRecord
  belongs_to :user

  enum :proficiency, { elementary: 0, limited_working: 1, professional_working: 2, full_professional: 3, native: 4 },
       default: :professional_working

  LABELS = {
    "elementary" => "Elementary",
    "limited_working" => "Limited working",
    "professional_working" => "Professional working",
    "full_professional" => "Full professional",
    "native" => "Native or bilingual"
  }.freeze

  validates :name, presence: true, length: { maximum: 60 },
                   uniqueness: { scope: :user_id, case_sensitive: false }

  normalizes :name, with: ->(name) { name.to_s.squish }

  scope :ordered, -> { order(proficiency: :desc, name: :asc) }

  def proficiency_label = LABELS[proficiency]

  # Matches LinkedIn's wording ("Native or bilingual proficiency") and plain words.
  def self.proficiency_from(text)
    t = text.to_s.downcase
    return :native if t.include?("native") || t.include?("bilingual")
    return :full_professional if t.include?("full")
    return :professional_working if t.include?("professional")
    return :limited_working if t.include?("limited")
    return :elementary if t.include?("elementary") || t.include?("basic")

    :professional_working
  end
end

# frozen_string_literal: true

# A role on someone's professional profile (LinkedIn-style "Experience").
class Experience < ApplicationRecord
  EMPLOYMENT_TYPES = [ "Full-time", "Part-time", "Self-employed", "Freelance", "Contract", "Internship",
                       "Volunteer", "Ministry" ].freeze

  belongs_to :user

  validates :title, :organization, presence: true, length: { maximum: 100 }
  validates :start_on, presence: true
  validates :employment_type, inclusion: { in: EMPLOYMENT_TYPES }, allow_blank: true
  validates :location, length: { maximum: 100 }
  validates :description, length: { maximum: 2000 }
  validate :ends_after_start

  before_save { self.end_on = nil if current? }

  # Current roles first, then most recent.
  scope :ordered, -> { order(current: :desc, start_on: :desc) }

  # The form uses <input type="month"> ("2024-05"); store the first of that month.
  def start_month = start_on&.strftime("%Y-%m")
  def end_month = end_on&.strftime("%Y-%m")

  def start_month=(value)
    self.start_on = self.class.month_to_date(value)
  end

  def end_month=(value)
    self.end_on = self.class.month_to_date(value)
  end

  def self.month_to_date(value)
    Date.strptime(value.to_s, "%Y-%m") if value.present?
  rescue Date::Error
    nil
  end

  # "May 2022 – Present", "Jan 2019 – Mar 2021"
  def date_range
    finish = current? || end_on.nil? ? "Present" : end_on.strftime("%b %Y")
    "#{start_on.strftime('%b %Y')} – #{finish}"
  end

  # "2 yrs 5 mos", like LinkedIn (counts the start month).
  def duration
    finish = current? || end_on.nil? ? Date.current : end_on
    months = ((finish.year * 12) + finish.month) - ((start_on.year * 12) + start_on.month) + 1
    years, rest = months.divmod(12)
    [ (years.positive? ? "#{years} yr#{'s' if years > 1}" : nil), (rest.positive? ? "#{rest} mo#{'s' if rest > 1}" : nil) ]
      .compact.join(" ").presence || "1 mo"
  end

  private

  def ends_after_start
    return if current? || end_on.blank? || start_on.blank?

    errors.add(:end_month, "must be after the start") if end_on < start_on
  end
end

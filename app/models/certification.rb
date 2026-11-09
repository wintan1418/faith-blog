# frozen_string_literal: true

# A license or certification on a professional profile (LinkedIn's
# "Licenses & certifications").
class Certification < ApplicationRecord
  belongs_to :user

  validates :name, presence: true, length: { maximum: 150 }
  validates :issuer, length: { maximum: 120 }
  validates :credential_url, length: { maximum: 500 },
                             format: { with: %r{\Ahttps://\S+\z}i, message: "must start with https://" }, allow_blank: true
  validate :expires_after_issued

  # Newest first; undated ones last.
  scope :ordered, -> { order(Arel.sql("issued_on DESC NULLS LAST"), :name) }

  def issued_month = issued_on&.strftime("%Y-%m")
  def expires_month = expires_on&.strftime("%Y-%m")

  def issued_month=(value)
    self.issued_on = Experience.month_to_date(value)
  end

  def expires_month=(value)
    self.expires_on = Experience.month_to_date(value)
  end

  def expired? = expires_on.present? && expires_on < Date.current

  # "Issued Jun 2022 · Expires Jun 2025"
  def dates
    [ (issued_on && "Issued #{issued_on.strftime('%b %Y')}"),
      (expires_on && "#{expired? ? 'Expired' : 'Expires'} #{expires_on.strftime('%b %Y')}") ].compact.join(" · ")
  end

  private

  def expires_after_issued
    return if issued_on.blank? || expires_on.blank?

    errors.add(:expires_month, "must be after the issue date") if expires_on < issued_on
  end
end

# frozen_string_literal: true

class Report < ApplicationRecord
  # Enums
  enum :status, { pending: 0, reviewed: 1, resolved: 2, dismissed: 3 }

  # Associations
  belongs_to :reporter, class_name: "User"
  belongs_to :reportable, polymorphic: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  # Validations
  validates :reason, presence: true, length: { minimum: 10, maximum: 500 }

  # Scopes
  scope :pending, -> { where(status: :pending) }
  scope :recent, -> { order(created_at: :desc) }

  # Instance methods
  def review!(moderator, resolution_status, notes = nil)
    update(
      status: resolution_status,
      reviewed_by: moderator,
      reviewed_at: Time.current,
      resolution_notes: notes
    )
  end
end


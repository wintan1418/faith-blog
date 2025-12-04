# frozen_string_literal: true

class ModerationLog < ApplicationRecord
  # Associations
  belongs_to :moderator, class_name: "User"
  belongs_to :target, polymorphic: true

  # Validations
  validates :action, presence: true

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :by_action, ->(action) { where(action: action) }
  scope :by_moderator, ->(moderator) { where(moderator: moderator) }

  # Class methods
  def self.log_action(moderator:, action:, target:, notes: nil, metadata: {})
    create(
      moderator: moderator,
      action: action,
      target: target,
      notes: notes,
      metadata: metadata
    )
  end
end


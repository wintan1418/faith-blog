# frozen_string_literal: true

class Mention < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :mentionable, polymorphic: true
  belongs_to :mentioned_by, polymorphic: true

  # Validations
  validates :user_id, uniqueness: {
    scope: [ :mentionable_type, :mentionable_id ],
    message: "already mentioned in this content"
  }

  # Scopes
  scope :for_user, ->(user) { where(user: user) }
  scope :in_posts, -> { where(mentionable_type: "Post") }
  scope :in_comments, -> { where(mentionable_type: "Comment") }
  scope :recent, -> { order(created_at: :desc) }
end

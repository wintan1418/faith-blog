# frozen_string_literal: true

class Bookmark < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :post

  # Validations
  validates :user_id, uniqueness: { scope: :post_id, message: "has already bookmarked this post" }

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
end


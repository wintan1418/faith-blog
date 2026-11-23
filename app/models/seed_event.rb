# frozen_string_literal: true

# One line in the Seeds ledger: who earned how many seeds, for what, and when.
# The ledger is the truth; users.seeds_total is a cached sum of it.
class SeedEvent < ApplicationRecord
  belongs_to :user
  belongs_to :source, polymorphic: true, optional: true

  validates :kind, inclusion: { in: ->(_) { Seeds::RULES.keys } }
  validates :points, numericality: { only_integer: true }
  validates :created_on, presence: true

  # Rows a public board may count. Seeds an author earned on an anonymous
  # breath stay in their own total but never on a board, so a leaderboard can
  # never hint at who wrote it.
  scope :public_board, -> { where(anonymous: false) }
  scope :since, ->(date) { where(created_on: date..) }
end

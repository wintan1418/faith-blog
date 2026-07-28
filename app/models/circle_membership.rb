# frozen_string_literal: true

class CircleMembership < ApplicationRecord
  belongs_to :circle, counter_cache: :members_count
  belongs_to :user

  enum :role, { member: 0, owner: 1 }

  validates :user_id, uniqueness: { scope: :circle_id, message: "is already in this circle" }
end

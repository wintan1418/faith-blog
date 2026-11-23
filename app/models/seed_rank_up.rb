# frozen_string_literal: true

# A rank a member reached, once. The rank-up notification points at it.
class SeedRankUp < ApplicationRecord
  belongs_to :user
  has_many :notifications, as: :notifiable, dependent: :destroy

  validates :rank_index, uniqueness: { scope: :user_id }

  def rank = Seeds::Rank.at(rank_index)
end

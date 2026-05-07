# frozen_string_literal: true

class PrayerIntercession < ApplicationRecord
  belongs_to :user
  belongs_to :post, counter_cache: :intercessions_count

  validates :user_id, uniqueness: { scope: :post_id, message: "is already in this prayer chain" }
end

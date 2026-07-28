# frozen_string_literal: true

class CirclePrayerAmen < ApplicationRecord
  # The inflector reads "amen" as an already-plural "…men" word and derives
  # the table as "circle_prayer_amen" — pin the real name.
  self.table_name = "circle_prayer_amens"

  belongs_to :circle_prayer, counter_cache: :amens_count
  belongs_to :user

  validates :user_id, uniqueness: { scope: :circle_prayer_id }
end

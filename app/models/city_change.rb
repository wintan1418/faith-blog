# frozen_string_literal: true

# One change of a member's city (Breathers around you): who, from, to, when.
# A member may make CHANGES_ALLOWED counted changes in any WINDOW, so nobody can
# hop from town to town to browse who lives there. Setting a first city and
# clearing it aren't counted. Staff see frequent movers in Admin → City changes.
class CityChange < ApplicationRecord
  CHANGES_ALLOWED = 2
  WINDOW = 30.days
  # Members with this many changes (counted or not) in WINDOW are listed for staff.
  WATCH_AT = 3

  belongs_to :user
  belongs_to :from_city, class_name: "City", optional: true
  belongs_to :to_city, class_name: "City", optional: true

  scope :recent, -> { where(created_at: WINDOW.ago..) }

  # When this member may change city again, or nil if they may now.
  def self.next_change_at(user_id, now: Time.current)
    times = where(user_id: user_id, counted: true, created_at: (now - WINDOW)..).order(:created_at).pluck(:created_at)
    return if times.size < CHANGES_ALLOWED

    times[times.size - CHANGES_ALLOWED] + WINDOW
  end

  # { user_id => number of changes } for members with WATCH_AT or more in WINDOW.
  def self.frequent_movers
    recent.group(:user_id).having("COUNT(*) >= ?", WATCH_AT).order(Arel.sql("COUNT(*) DESC")).count
  end
end

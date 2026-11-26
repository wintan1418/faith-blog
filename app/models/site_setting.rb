# frozen_string_literal: true

# Small named switches the admin can flip from the console, e.g.
#   SiteSetting.on?("celebrations.auto_activate_presets")
class SiteSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true, length: { maximum: 120 }

  def self.[](key) = find_by(key: key.to_s)&.value

  def self.on?(key) = self[key] == "1"

  def self.set(key, value)
    row = find_or_initialize_by(key: key.to_s)
    row.update!(value: value.to_s)
    row.value
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def self.switch(key, on) = set(key, on ? "1" : "0")
end

# frozen_string_literal: true

# The newest app version on the store, and the oldest one still allowed in.
# Admins set these on Admin → App versions after Google Play approves a release.
class AppRelease < ApplicationRecord
  PLATFORMS = %w[android].freeze
  VERSION_FORMAT = /\A\d+(\.\d+){0,3}\z/

  validates :platform, inclusion: { in: PLATFORMS }, uniqueness: true
  validates :latest_version, :minimum_version, format: { with: VERSION_FORMAT, message: "should look like 1.0.8" }, allow_blank: true
  validate :minimum_not_above_latest

  normalizes :latest_version, :minimum_version, with: ->(v) { v.to_s.strip.presence }

  def self.android = find_or_initialize_by(platform: "android")

  def latest = version(latest_version)
  def minimum = version(minimum_version)

  # Members who last opened an older Android app than the latest release.
  def outdated_users
    return User.none unless latest

    behind = User.where.not(android_app_version: nil).distinct.pluck(:android_app_version)
                 .select { |v| (ver = version(v)) && ver < latest }
    User.where(android_app_version: behind)
  end

  # { "1.0.8" => 12, "1.0.6" => 3, … }, newest first.
  def self.android_version_counts
    User.where.not(android_app_version: nil).group(:android_app_version).count
        .sort_by { |v, _| Gem::Version.new(v) rescue Gem::Version.new("0") }.reverse.to_h
  end

  private

  def version(value)
    value.present? && value.match?(VERSION_FORMAT) ? Gem::Version.new(value) : nil
  end

  def minimum_not_above_latest
    return unless minimum && latest && minimum > latest

    errors.add(:minimum_version, "can't be newer than the latest version")
  end
end

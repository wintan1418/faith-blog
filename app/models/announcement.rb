# frozen_string_literal: true

class Announcement < ApplicationRecord
  belongs_to :user, optional: true

  enum :kind, { release: 0, new_member: 1, custom: 2 }, prefix: :kind

  validates :title, presence: true, length: { maximum: 160 }
  validates :kicker, length: { maximum: 80 }, allow_blank: true

  before_validation :default_published_at, on: :create

  scope :active, -> {
    where("published_at IS NULL OR published_at <= ?", Time.current)
      .where("expires_at IS NULL OR expires_at >= ?", Time.current)
  }

  scope :releases,    -> { kind_release }
  scope :new_members, -> { kind_new_member }

  # Most recent active release announcement, used by the feed banner.
  def self.latest_release
    releases.active.order(published_at: :desc).first
  end

  # New-member events from the last 7 days, used in the feed timeline.
  def self.recent_new_members(limit: 8)
    new_members.active.includes(:user).order(published_at: :desc).limit(limit)
  end

  private

  def default_published_at
    self.published_at ||= Time.current
  end
end

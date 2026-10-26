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

  # "What's new" slides: each line of a release's body is one feature.
  #   "🎂 Birthdays — Celebrate your brethren on their day"
  # (emoji optional; " — ", " - " or ": " separates the title from the description).
  Slide = Struct.new(:emoji, :title, :text, keyword_init: true)
  EMOJI_START = /\A(\p{Extended_Pictographic}(?:\uFE0F|\u200D\p{Extended_Pictographic})*)\s*/

  def slides
    body.to_s.lines.map { |l| l.strip.sub(/\A[-*•]\s+/, "") }.compact_blank.map do |line|
      emoji = line[EMOJI_START, 1]
      line = line.sub(EMOJI_START, "") if emoji
      title, text = line.split(/\s+[—–-]\s+|:\s+/, 2)
      Slide.new(emoji: emoji || "✨", title: title.to_s.strip, text: text.to_s.strip.presence)
    end
  end

  # The release this person hasn't seen yet (none for brand-new members: they get the full app anyway).
  def self.unseen_release_for(user)
    return unless user

    release = latest_release
    return unless release && release.slides.any?
    return if user.seen_release_id.to_i >= release.id
    return if (release.published_at || release.created_at) < user.created_at

    release
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

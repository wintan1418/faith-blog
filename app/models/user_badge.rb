# frozen_string_literal: true

# Spiritual and community milestones. The catalog defines each badge and
# the condition that earns it; `check!` awards anything newly earned and
# notifies the user. Conditions are cheap count/exists queries, safe to
# re-run on every trigger.
class UserBadge < ApplicationRecord
  belongs_to :user
  has_many :notifications, as: :notifiable, dependent: :destroy

  validates :slug, presence: true, uniqueness: { scope: :user_id }

  CATALOG = {
    "first_breath" => {
      name: "First Breath", emoji: "🌱",
      blurb: "Published your first breath",
      earned: ->(u) { u.posts.published.exists? }
    },
    "streak_7" => {
      name: "Seven Days of Breath", emoji: "🔥",
      blurb: "Breathed seven days in a row",
      earned: ->(u) { u.current_breath_streak.to_i >= 7 }
    },
    "streak_30" => {
      name: "Faithful Month", emoji: "🌟",
      blurb: "A thirty-day breath streak",
      earned: ->(u) { u.current_breath_streak.to_i >= 30 }
    },
    "encourager" => {
      name: "Encourager", emoji: "💪",
      blurb: "Gave 100 reactions to the brethren",
      earned: ->(u) { Like.where(user: u).count >= 100 }
    },
    "prayer_warrior" => {
      name: "Prayer Warrior", emoji: "🙏",
      blurb: "Joined 10 prayer chains",
      earned: ->(u) { PrayerIntercession.where(user: u).count >= 10 }
    },
    "testimony" => {
      name: "Testimony", emoji: "🕊️",
      blurb: "A prayer you shared was answered",
      earned: ->(u) { u.posts.where(prayer_status: :prayer_answered).exists? }
    },
    "voice_in_the_assembly" => {
      name: "Voice in the Assembly", emoji: "🧵",
      blurb: "Added 25 comments to the conversation",
      earned: ->(u) { Comment.where(user: u).count >= 25 }
    },
    "scholar" => {
      name: "Scholar", emoji: "📖",
      blurb: "Played 10 rounds in the games room",
      earned: ->(u) { u.game_attempts.count >= 10 }
    },
    "perfect_round" => {
      name: "Perfect Round", emoji: "🎯",
      blurb: "A flawless game round (5+ questions)",
      earned: ->(u) { u.game_attempts.where("score = max_score AND max_score >= 5").exists? }
    },
    "gatherer" => {
      name: "Gatherer", emoji: "🤝",
      blurb: "Someone you invited joined the brethren",
      earned: ->(u) { Invitation.accepted.where(inviter: u).exists? }
    }
  }.freeze

  def self.check!(user)
    return unless user

    earned_slugs = where(user: user).pluck(:slug)
    CATALOG.each do |slug, badge|
      next if earned_slugs.include?(slug)
      next unless badge[:earned].call(user)

      awarded = create!(user: user, slug: slug, awarded_at: Time.current)
      Notification.create(
        user: user,
        actor: user,
        notifiable: awarded,
        notification_type: :badge_earned
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # Raced with another trigger — the badge exists, which is all we want.
    end
  end

  def info
    CATALOG[slug] || { name: slug.humanize, emoji: "✦", blurb: "" }
  end
end

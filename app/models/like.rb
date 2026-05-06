# frozen_string_literal: true

class Like < ApplicationRecord
  ENUM_TO_EMOJI = { "amen" => "🙏", "praying" => "✝️", "encourage" => "💪", "love" => "❤️", "inspired" => "✨" }.freeze

  enum :reaction_type, { amen: 0, praying: 1, encourage: 2, love: 3, inspired: 4 }

  belongs_to :user
  belongs_to :likeable, polymorphic: true, counter_cache: :likes_count

  validates :user_id, uniqueness: { scope: [ :likeable_type, :likeable_id ], message: "has already reacted to this" }

  scope :by_reaction, ->(reaction) { where(reaction_type: reaction) }
  scope :by_emoji,    ->(emoji)    { where(reaction_emoji: emoji) }

  def display_emoji
    reaction_emoji.presence || ENUM_TO_EMOJI[reaction_type.to_s] || "👍"
  end

  def self.reaction_emoji(reaction)
    ENUM_TO_EMOJI[reaction.to_s] || "👍"
  end

  def self.reaction_label(reaction)
    case reaction.to_sym
    when :amen      then "Amen"
    when :praying   then "Praying"
    when :encourage then "Be Encouraged"
    when :love      then "Love"
    when :inspired  then "Inspired"
    else "Like"
    end
  end

  # Map an arbitrary emoji to the legacy enum value when possible,
  # so old code paths and counters keep working.
  def self.enum_for_emoji(emoji)
    ENUM_TO_EMOJI.invert[emoji] || "amen"
  end
end

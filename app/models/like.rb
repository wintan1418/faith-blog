# frozen_string_literal: true

class Like < ApplicationRecord
  # Enums - Faith-based reactions
  enum :reaction_type, { amen: 0, praying: 1, encourage: 2, love: 3, inspired: 4 }

  # Associations
  belongs_to :user
  belongs_to :likeable, polymorphic: true, counter_cache: :likes_count

  # Validations
  validates :user_id, uniqueness: { scope: [:likeable_type, :likeable_id], message: "has already reacted to this" }

  # Scopes
  scope :by_reaction, ->(reaction) { where(reaction_type: reaction) }

  # Class methods
  def self.reaction_emoji(reaction)
    case reaction.to_sym
    when :amen then "🙏"
    when :praying then "✝️"
    when :encourage then "💪"
    when :love then "❤️"
    when :inspired then "✨"
    else "👍"
    end
  end

  def self.reaction_label(reaction)
    case reaction.to_sym
    when :amen then "Amen"
    when :praying then "Praying"
    when :encourage then "Be Encouraged"
    when :love then "Love"
    when :inspired then "Inspired"
    else "Like"
    end
  end
end


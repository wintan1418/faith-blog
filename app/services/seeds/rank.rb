# frozen_string_literal: true

module Seeds
  # Ranks by seeds total. An active member (a breath and a few comments a day)
  # earns 30–60 seeds a day, so Sprout comes in the first days, Branch within a
  # few weeks, and Cedar of Lebanon only after many months of faithfulness.
  Rank = Data.define(:index, :key, :name, :emoji, :icon, :threshold) do
    def self.all = Rank::LIST

    def self.for(total)
      Rank::LIST.reverse.find { |rank| total.to_i >= rank.threshold } || Rank::LIST.first
    end

    def self.at(index) = Rank::LIST[index.to_i.clamp(0, Rank::LIST.size - 1)]

    def next = Rank::LIST[index + 1]

    # "a Sapling", "an Oak", "a Cedar of Lebanon".
    def a_name = "#{name.match?(/\A[AEIOU]/) ? 'an' : 'a'} #{name}"

    def top? = self.next.nil?

    # 0..100 through this rank towards the next.
    def progress(total)
      return 100 if top?

      span = self.next.threshold - threshold
      (((total.to_i - threshold) * 100.0) / span).clamp(0, 100).floor
    end

    def seeds_to_next(total)
      top? ? 0 : [ self.next.threshold - total.to_i, 0 ].max
    end
  end

  Rank::LIST = [
    Rank.new(index: 0, key: "seedling", name: "Seedling",         emoji: "🌱", icon: "sprout",  threshold: 0),
    Rank.new(index: 1, key: "sprout",   name: "Sprout",           emoji: "☘️", icon: "leaf",    threshold: 50),
    Rank.new(index: 2, key: "sapling",  name: "Sapling",          emoji: "🌿", icon: "sapling", threshold: 150),
    Rank.new(index: 3, key: "branch",   name: "Branch",           emoji: "🍃", icon: "branch",  threshold: 400),
    Rank.new(index: 4, key: "fruitful", name: "Fruitful",         emoji: "🍇", icon: "grapes",  threshold: 1_000),
    Rank.new(index: 5, key: "oak",      name: "Oak",              emoji: "🌳", icon: "tree",    threshold: 2_500),
    Rank.new(index: 6, key: "cedar",    name: "Cedar of Lebanon", emoji: "🌲", icon: "cedar",   threshold: 6_000)
  ].freeze
end

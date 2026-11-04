# frozen_string_literal: true

module Bots
  # The bots behind the Updates tab: who they are, what they cover, and how
  # much each may post in a day so the tab never floods.
  module Catalog
    Bot = Data.define(:key, :name, :emoji, :tagline, :daily_cap, :fresh_for, :topics)

    NEWS_TOPICS = {
      "world"    => "World",
      "politics" => "Politics",
      "tech"     => "Tech & AI",
      "science"  => "Science & discoveries",
      "health"   => "Health",
      "business" => "Business",
      "food"     => "Food",
      "faith"    => "Faith"
    }.freeze

    ALL = [
      Bot.new(key: "news", name: "Brethreign News", emoji: "📰",
              tagline: "The day's stories from around the world",
              daily_cap: 60, fresh_for: 2.days, topics: NEWS_TOPICS),
      Bot.new(key: "sports", name: "Brethreign Sports", emoji: "🏆",
              tagline: "Results and big moments across sport",
              daily_cap: 20, fresh_for: 2.days, topics: {}),
      Bot.new(key: "jobs", name: "Brethreign Jobs", emoji: "💼",
              tagline: "Remote jobs open to people anywhere",
              daily_cap: 20, fresh_for: 14.days, topics: {}),
      Bot.new(key: "courses", name: "Brethreign Learn", emoji: "🎓",
              tagline: "Free courses, scholarships and fellowships",
              daily_cap: 12, fresh_for: 30.days, topics: {})
    ].freeze

    BY_KEY = ALL.index_by(&:key).freeze

    module_function

    def keys = BY_KEY.keys
    def find(key) = BY_KEY[key.to_s]
    def fetch(key) = BY_KEY.fetch(key.to_s)
  end
end

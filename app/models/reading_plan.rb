# frozen_string_literal: true

# Plain value class for Bible reading plans. Plans are static data in
# config/reading_plans.yml — content rarely changes and we don't need
# a DB table. UserReadingPlan tracks each member's progress.
class ReadingPlan
  attr_reader :slug, :title, :description, :days

  CONFIG_PATH = Rails.root.join("config", "reading_plans.yml")

  def initialize(attrs)
    @slug        = attrs["slug"].to_s
    @title       = attrs["title"].to_s
    @description = attrs["description"].to_s
    @days        = Array(attrs["days"]).map(&:with_indifferent_access)
  end

  def day(n)
    days.find { |d| d[:day].to_i == n.to_i }
  end

  def length_label
    "#{days.size} days"
  end

  def self.all
    @all ||= load_from_yaml.map { |attrs| new(attrs) }
  end

  def self.find(slug)
    all.find { |p| p.slug == slug.to_s }
  end

  def self.load_from_yaml
    return [] unless File.exist?(CONFIG_PATH)

    YAML.safe_load_file(CONFIG_PATH, permitted_classes: [], aliases: true) || []
  rescue StandardError => e
    Rails.logger.warn("[reading_plans] failed to load: #{e.message}")
    []
  end

  # Reset memoization — useful in tests / dev when YAML changes.
  def self.reload!
    @all = nil
  end
end

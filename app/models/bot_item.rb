# frozen_string_literal: true

# One story, job or course a bot brought in. Members see live items in the
# Updates tab; skipped ones are kept briefly so the same link isn't
# reconsidered on every run.
class BotItem < ApplicationRecord
  belongs_to :bot_source
  has_many :likes, as: :likeable, dependent: :destroy

  enum :status, { live: 0, hidden: 1, skipped: 2 }

  validates :title, :url, :url_digest, :published_at, presence: true
  validates :url_digest, uniqueness: true
  validates :url, format: { with: %r{\Ahttps://[^\s]+\z}i }

  # The link to the original, only ever an https:// address.
  def safe_url
    url if url.to_s.match?(%r{\Ahttps://[^\s]+\z}i)
  end

  scope :newest, -> { order(published_at: :desc, id: :desc) }

  def self.digest_for(url) = Digest::SHA256.hexdigest(normalize_url(url))

  # Same story, same digest: drop tracking params and #fragments.
  def self.normalize_url(url)
    uri = URI.parse(url.to_s.strip)
    if uri.query
      kept = URI.decode_www_form(uri.query).reject { |k, _| k.start_with?("utm_") || %w[at_medium at_campaign ref cmp].include?(k) }
      uri.query = kept.any? ? URI.encode_www_form(kept) : nil
    end
    uri.fragment = nil
    uri.to_s.downcase.chomp("/")
  rescue URI::InvalidURIError
    url.to_s.strip.downcase
  end

  def bot_info = Bots::Catalog.fetch(bot)
  def topic_label = bot_info.topics[topic]
  def source_name = bot_source.name

  # Shown under the title on job cards: "Acme · Anywhere · $80k".
  def detail_line
    details.values_at("company", "location", "salary").compact_blank.join(" · ").presence
  end

  def visible_to?(_user) = live?
end

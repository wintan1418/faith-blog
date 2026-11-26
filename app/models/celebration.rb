# frozen_string_literal: true

# Brethreign Celebrates: one special occasion (Christmas, Easter, Nigeria's
# Independence Day…). While it is live and running, members it is meant for
# see a banner on the feed, a lighter strip on other main pages, a one-time
# pop-up and can share a greeting card.
#
# Nothing goes live on its own: an occasion is a draft until an admin
# activates it (or the admin turned on "auto-activate presets").
class Celebration < ApplicationRecord
  include AttachmentValidatable

  AUTO_ACTIVATE_SETTING = "celebrations.auto_activate_presets"
  ARTWORK_MAX_BYTES = 5.megabytes

  # Subtle moving touches drawn over the banner (none when the member asked
  # for reduced motion).
  EFFECTS = {
    "none" => "None",
    "confetti" => "Soft confetti",
    "leaves" => "Falling leaves",
    "lights" => "Twinkling lights",
    "petals" => "Drifting petals",
    "stars" => "Quiet stars"
  }.freeze

  # The countries offered as tick boxes in the admin form (any ISO code can
  # be typed in as well).
  COUNTRIES = {
    "NG" => "Nigeria", "US" => "United States", "GB" => "United Kingdom", "GH" => "Ghana",
    "KE" => "Kenya", "ZA" => "South Africa", "CA" => "Canada", "UG" => "Uganda",
    "IE" => "Ireland", "AU" => "Australia"
  }.freeze

  enum :status, { draft: 0, live: 1 }, default: :draft
  enum :audience, { everyone: 0, countries: 1 }, prefix: :for, default: :everyone

  belongs_to :post, optional: true
  has_one_attached :artwork

  # The admin form sends the start and end as local times in `time_zone`.
  attribute :starts_local, :string
  attribute :ends_local, :string
  attribute :post_link, :string
  attribute :country_list, :string

  before_validation :apply_local_times, :normalize_fields, :resolve_post_link, :fill_scripture_text

  validates :name, presence: true, length: { maximum: 80 }
  validates :greeting_title, presence: true, length: { maximum: 90 }
  validates :message, length: { maximum: 400 }
  validates :scripture_reference, length: { maximum: 60 }
  validates :scripture_text, length: { maximum: 600 }
  validates :hashtag, length: { maximum: 40 }, format: { with: /\A[A-Za-z0-9_]+\z/ }, allow_blank: true
  validates :emblem, length: { maximum: 16 }
  validates :accent_color, format: { with: /\A#\h{6}\z/, message: "must be a colour like #0e5c43" }
  validates :effect, inclusion: { in: EFFECTS.keys }
  validates :starts_at, :ends_at, presence: true
  validate :ends_after_start, :countries_chosen, :post_link_found, :known_time_zone
  validate { validate_image_attachment(:artwork, max_bytes: ARTWORK_MAX_BYTES) }

  scope :running_at, ->(time) { where("celebrations.starts_at <= ? AND celebrations.ends_at > ?", time, time) }
  scope :upcoming_first, -> { order(:starts_at) }

  # The live occasion this member should see now, or nil: not one they have
  # closed. One aimed at their country comes before one for everyone (so on
  # US Thanksgiving an American member sees Thanksgiving first).
  def self.current_for(user, country: nil, at: Time.current)
    country = country.to_s.upcase.presence
    live.running_at(at).includes(:post, artwork_attachment: :blob).to_a
        .select { |c| c.for_country?(country) && !user&.card_dismissed?(c.dismissal_key) }
        .min_by { |c| [ c.for_countries? ? 0 : 1, c.ends_at, c.id ] }
  end

  def self.auto_activate_presets? = SiteSetting.on?(AUTO_ACTIVATE_SETTING)

  def for_country?(code)
    for_everyone? || (code.present? && country_codes.include?(code.to_s.upcase))
  end

  def running?(at = Time.current) = starts_at.present? && ends_at.present? && starts_at <= at && ends_at > at
  def showing? = live? && running?
  def preset? = preset_key.present?

  # Account-level "closed" keys (User#dismiss_card!).
  def dismissal_key = "celebrate-#{id}"
  def popup_key = "celebrate-pop-#{id}"

  def zone = ActiveSupport::TimeZone[time_zone.to_s] || Time.zone
  def local_starts_at = starts_at&.in_time_zone(zone)
  def local_ends_at = ends_at&.in_time_zone(zone)

  def starts_local = super.presence || local_starts_at&.strftime("%Y-%m-%dT%H:%M")
  def ends_local = super.presence || local_ends_at&.strftime("%Y-%m-%dT%H:%M")
  def country_list = super.presence || (country_codes - COUNTRIES.keys).join(", ")
  def post_link = super.presence || (post && Rails.application.routes.url_helpers.post_path(post))

  def hashtag_text = hashtag.present? ? "##{hashtag}" : nil

  # The text put in the composer by "Share a greeting".
  def greeting_prefill
    parts = [ "#{greeting_title}, brethren! #{emblem}".strip ]
    parts << "“#{scripture_text.squish}” (#{scripture_reference})" if scripture_text.present? && scripture_reference.present?
    parts << hashtag_text if hashtag_text
    parts.join("\n\n") + " "
  end

  # The text that goes with "Send to a friend".
  def friend_message(url)
    [ "#{greeting_title}! #{emblem}".strip, message.presence, url ].compact.join("\n\n")
  end

  def audience_label
    return "Everyone" if for_everyone?

    country_codes.map { |c| COUNTRIES[c] || c }.to_sentence
  end

  def status_label
    return "Draft" if draft?
    return "Live now" if running?

    ends_at.past? ? "Finished" : "Scheduled"
  end

  private

  def apply_local_times
    self.starts_at = zone.parse(attributes["starts_local"]) if attributes["starts_local"].present?
    self.ends_at = zone.parse(attributes["ends_local"]) if attributes["ends_local"].present?
  rescue ArgumentError
    errors.add(:base, "Start and end must be dates and times")
  end

  def normalize_fields
    self.hashtag = hashtag.to_s.strip.delete_prefix("#").presence
    self.accent_color = accent_color.to_s.strip.downcase
    self.emblem = emblem.to_s.strip.presence
    self.scripture_reference = scripture_reference.to_s.squish.presence
    self.scripture_text = scripture_text.to_s.strip.presence
    typed = attributes["country_list"].to_s.upcase.scan(/\b[A-Z]{2}\b/)
    self.country_codes = (Array(country_codes).compact_blank.map { |c| c.to_s.strip.upcase } + typed)
                           .select { |c| c.match?(/\A[A-Z]{2}\z/) }.uniq
  end

  # "https://brethreign.com/posts/happy-thanksgiving", "/posts/123" or a slug.
  def resolve_post_link
    raw = attributes["post_link"].to_s.strip
    return if raw.blank? && !attribute_changed?(:post_link)
    return self.post = nil if raw.blank?

    slug = raw.sub(%r{\A(?:https?://[^/]+)?/}, "").delete_prefix("posts/").split(/[?#]/).first.to_s
    @post_not_found = !(self.post = Post.friendly.find(slug, allow_nil: true))
  end

  # KJV from the app's Bible text when the admin gave only a reference.
  def fill_scripture_text
    return if scripture_reference.blank?

    reference = Scripture::Reference.parse(scripture_reference)
    return errors.add(:scripture_reference, "isn't a Bible reference we know") unless reference

    self.scripture_reference = reference.to_s
    # A new reference with the old verse text left in place gets the new text.
    stale = persisted? && scripture_reference_changed? && !scripture_text_changed?
    return if scripture_text.present? && !stale

    self.scripture_text = Scripture::Passage.new(reference).primary_text.presence
  rescue StandardError => e
    Rails.logger.warn("[celebration] scripture lookup failed: #{e.message}")
  end

  def ends_after_start
    errors.add(:ends_at, "must be after the start") if starts_at && ends_at && ends_at <= starts_at
  end

  def countries_chosen
    errors.add(:country_codes, "— choose at least one country (or Everyone)") if for_countries? && country_codes.empty?
  end

  def known_time_zone
    errors.add(:time_zone, "isn't a known time zone") unless ActiveSupport::TimeZone[time_zone.to_s]
  end

  def post_link_found
    errors.add(:post_link, "doesn't match a breath on Brethreign") if @post_not_found
  end
end

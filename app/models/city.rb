# frozen_string_literal: true

# A real place from GeoNames (geonames.org, CC BY 4.0), loaded by
# `bin/rails cities:import`. Members pick one as their city; we keep only the
# city and its centre point, never where the member actually is.
class City < ApplicationRecord
  has_many :profiles, dependent: :nullify

  EARTH_RADIUS_KM = 6371.0
  # Words a region's name ends with that people usually leave off ("Ondo State" → "Ondo").
  REGION_SUFFIX = /\s+(state|county|province|region|governorate|prefecture|district|territory)\z/i
  # Ways people write a country that GeoNames doesn't list as its name.
  COUNTRY_ALIASES = {
    "usa" => "US", "us" => "US", "america" => "US", "united states of america" => "US",
    "uk" => "GB", "britain" => "GB", "great britain" => "GB", "england" => "GB", "scotland" => "GB", "wales" => "GB",
    "uae" => "AE", "drc" => "CD", "naija" => "NG"
  }.freeze
  # Locations that say nothing about where someone is.
  VAGUE = %w[online remote worldwide everywhere global earth anywhere nowhere heaven internet].freeze

  validates :geonames_id, presence: true, uniqueness: true
  validates :name, :ascii_name, :country_code, :country_name, :lat, :lng, presence: true

  before_validation :fill_search_fields

  def self.normalize(text) = MatchKey.for(text).to_s

  # "|akure|akuce|akure|" from the name and its spellings, plus each later word
  # of a multi-word name ("port harcourt" also finds "harcourt").
  def self.tokens_for(*names)
    keys = names.flatten.compact.map { |n| normalize(n) }.compact_blank
    keys += keys.flat_map { |k| words = k.split; (1...words.size).map { |i| words[i..].join(" ") } }
    keys = keys.select { |k| k.length >= 3 || keys.first == k }.uniq.first(40)
    keys.empty? ? "" : "|#{keys.join('|')}|"
  end

  # Spellings worth searching by: proper names in plain letters, not codes ("LON")
  # or lower-case transliterations ("akule").
  def self.useful_alternates(list)
    list.to_s.split(",").map(&:strip).select do |n|
      n.length.between?(3, 40) && n.match?(/\A[A-Z][A-Za-z' .\-]+\z/) && n != n.upcase
    end.first(15)
  end

  # Type-ahead: prefix match on any name, exact names first, then bigger places,
  # nudged towards the visitor's country. "Akure, Nigeria" narrows by region/country.
  def self.search(query, country: nil, limit: 8)
    name, qualifier = split_query(query)
    return none if name.length < 2

    scope = where("cities.search_tokens LIKE ?", "%|#{sanitize_sql_like(name)}%")
    scope = narrowed_by(scope, qualifier)
    hint = country.to_s.upcase[/\A[A-Z]{2}\z/]
    like = sanitize_sql_like(name)
    # The place's own name beats a spelling or a later word ("lon" → London before Chợ Lớn).
    rank = sanitize_sql_array([
      "(CASE WHEN cities.search_key = :name THEN 3 WHEN cities.search_key LIKE :prefix THEN 2 " \
      "WHEN cities.search_tokens LIKE :exact THEN 1 ELSE 0 END) DESC, " \
      "(LN(cities.population + 10) + CASE WHEN cities.country_code = :hint THEN 3 ELSE 0 END) DESC, cities.id",
      name: name, prefix: "#{like}%", exact: "%|#{like}|%", hint: hint.to_s
    ])
    scope.order(Arel.sql(rank)).limit(limit)
  end

  # Best guess for free text like "Akure, Ondo State, Nigeria" (for the backfill
  # and LinkedIn imports). Returns a Match; only :matched carries a city.
  Match = Struct.new(:status, :city, :candidates, keyword_init: true) do
    def matched? = status == :matched
  end

  def self.match(text)
    name, qualifier = split_query(text)
    return Match.new(status: :blank, candidates: []) if name.blank?
    return Match.new(status: :vague, candidates: []) if VAGUE.include?(name)
    # "Nigeria", "USA 🇺🇸": a country is not a city (it once matched Aba and Worcester).
    return Match.new(status: :country_only, candidates: []) if country_name?(name)
    # "Ekiti, Nigeria": a state with no city of that name (it once matched Ado-Ekiti).
    return Match.new(status: :region_only, candidates: []) if region_name?(name) && !city_name?(name)

    exact = narrowed_by(where("cities.search_tokens LIKE ?", "%|#{sanitize_sql_like(name)}|%"), qualifier)
              .order(population: :desc).limit(5).to_a
    if exact.empty?
      region = where("LOWER(cities.admin1_name) = :n OR LOWER(cities.admin1_name) LIKE :s", n: name, s: "#{name} %").exists?
      return Match.new(status: region ? :region_only : :none, candidates: [])
    end

    top, second = exact
    # Without a region or country, only take a name that clearly means one place
    # ("London" is London, England; two similar-sized Springfields are a guess).
    if qualifier.blank? && second && second.population * 3 > top.population
      return Match.new(status: :ambiguous, candidates: exact)
    end

    Match.new(status: :matched, city: top, candidates: exact)
  end

  def self.country_name?(name)
    COUNTRY_ALIASES.key?(name) || where("LOWER(cities.country_name) = ?", name).exists?
  end

  def self.region_name?(name)
    short = name.sub(REGION_SUFFIX, "").strip
    where("LOWER(cities.admin1_name) IN (:names)", names: [ name, short, "#{short} state" ].uniq).exists?
  end

  def self.city_name?(name)
    # "New York" is a state and the start of "New York City", so it stays a city.
    where("LOWER(cities.ascii_name) = :n OR LOWER(cities.name) = :n OR LOWER(cities.ascii_name) LIKE :p",
          n: name, p: "#{sanitize_sql_like(name)} %").exists?
  end

  def self.best_match(text)
    match = match(text)
    match.city if match.matched?
  end

  # The nearest city to a point (used once by "Use my location"; the point is never stored).
  def self.nearest(lat, lng)
    lat = Float(lat)
    lng = Float(lng)
    return nil unless lat.between?(-90, 90) && lng.between?(-180, 180)

    [ 0.5, 2, 8 ].each do |span|
      near = where(lat: (lat - span)..(lat + span), lng: (lng - span * 2)..(lng + span * 2))
               .order(Arel.sql(distance_sql(lat, lng))).first
      return near if near
    end
    nil
  rescue ArgumentError, TypeError
    nil
  end

  # Great-circle distance in km from :lat/:lng to each city's centre (haversine),
  # as SQL with named binds: where("#{City::DISTANCE_SQL} <= :km", lat:, lng:, km:).
  DISTANCE_SQL = "(#{EARTH_RADIUS_KM} * 2 * ASIN(SQRT(LEAST(1.0, " \
                 "POWER(SIN(RADIANS(cities.lat - :lat) / 2), 2) + " \
                 "COS(RADIANS(:lat)) * COS(RADIANS(cities.lat)) * POWER(SIN(RADIANS(cities.lng - :lng) / 2), 2)))))"

  def self.distance_sql(lat, lng)
    sanitize_sql_array([ DISTANCE_SQL, { lat: lat.to_f, lng: lng.to_f } ])
  end

  def distance_km_to(other)
    rad = Math::PI / 180
    dlat = (other.lat - lat) * rad
    dlng = (other.lng - lng) * rad
    a = Math.sin(dlat / 2)**2 + Math.cos(lat * rad) * Math.cos(other.lat * rad) * Math.sin(dlng / 2)**2
    EARTH_RADIUS_KM * 2 * Math.asin(Math.sqrt([ a, 1.0 ].min))
  end

  # "Ondo" for "Ondo State"; nil when it would only repeat the city ("Lagos, Lagos").
  def region
    short = admin1_name.to_s.sub(REGION_SUFFIX, "").strip
    short if short.present? && !short.casecmp?(name) && !short.casecmp?(ascii_name)
  end

  # "Akure, Ondo, Nigeria": what the profile's location text becomes.
  def label = [ name, region, country_name ].compact_blank.join(", ").first(100)

  def as_json(*) = { id: id, name: name, label: label, region: region, country: country_name }

  def self.split_query(text)
    parts = text.to_s.split(",")
    [ normalize(parts.first), normalize(parts.drop(1).join(" ")) ]
  end

  # Keeps cities whose region or country fits the words after the comma.
  def self.narrowed_by(scope, qualifier)
    return scope if qualifier.blank?

    short = qualifier.sub(REGION_SUFFIX, "")
    words = qualifier.split
    codes = [ COUNTRY_ALIASES[qualifier], COUNTRY_ALIASES[words.last] ].compact
    # Only the last part is the country in "Ikeja, Lagos, Nigeria"; the middle is the region.
    country_part = words.last.to_s
    scope.where(
      "LOWER(cities.country_name) LIKE :q OR LOWER(cities.country_name) LIKE :last OR LOWER(cities.admin1_name) LIKE :short " \
      "OR LOWER(cities.country_code) IN (:words) OR LOWER(cities.admin1_code) IN (:words) OR cities.country_code IN (:codes)",
      q: "#{sanitize_sql_like(qualifier)}%", last: "#{sanitize_sql_like(country_part)}%",
      short: "#{sanitize_sql_like(short)}%", words: words.presence || [ "" ], codes: codes.presence || [ "" ]
    )
  end
  private_class_method :narrowed_by

  private

  def fill_search_fields
    self.ascii_name = name if ascii_name.blank?
    self.search_key = self.class.normalize(ascii_name.presence || name)
    self.search_tokens = self.class.tokens_for(ascii_name, name) if search_tokens.blank?
  end
end

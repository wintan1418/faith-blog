# frozen_string_literal: true

# Matches members' free-text locations ("Akure", "Akure, Ondo State, Nigeria",
# "Houston, TX") to real cities. Best effort: unclear text (two places of a
# similar size, a state with no city, "Online") is left alone and reported.
# Dry run by default; `apply: true` saves the city (and tidies the location text).
class CityBackfill
  Result = Struct.new(:profile_id, :location, :status, :city, :candidates, keyword_init: true)

  def initialize(apply: false, log: $stdout)
    @apply = apply
    @log = log
  end

  def call
    results = Profile.where(city_id: nil).where.not(location: [ nil, "" ]).order(:id).map do |profile|
      match = City.match(profile.location)
      profile.update(city: match.city) if @apply && match.matched?
      Result.new(profile_id: profile.id, location: profile.location_before_last_save || profile.location,
                 status: match.status, city: match.city, candidates: match.candidates)
    end
    report(results)
    results
  end

  private

  def report(results)
    @log.puts(@apply ? "Backfill (APPLIED):" : "Backfill dry run (nothing saved; APPLY=1 to save):")
    results.each do |r|
      detail = case r.status
      when :matched then "→ #{r.city.label} (##{r.city.geonames_id})"
      when :ambiguous then "?? could be #{r.candidates.first(3).map(&:label).join(' / ')}"
      when :region_only then "-- a state/region, no city named"
      when :vague then "-- not a place"
      else "-- no city found"
      end
      @log.puts format("  profile %-6d %-34s %s", r.profile_id, r.location.to_s.first(34).inspect, detail)
    end
    tally = results.group_by(&:status).transform_values(&:size)
    @log.puts "Total #{results.size}: " + tally.map { |status, n| "#{status} #{n}" }.join(", ")
  end
end

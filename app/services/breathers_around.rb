# frozen_string_literal: true

# "Breathers around you": members who chose to be found, in the viewer's city,
# within 50 km of it, then elsewhere in their country.
#
# Privacy rules (all enforced here, for every list, count and map dot):
#   - only members who turned on "Show me in Breathers around you" and have a city
#   - their city visibility allows this viewer (everyone, or connections only)
#   - never the viewer, blocked people (either way), deactivated accounts,
#     under-18s, or members who haven't been on for INACTIVE_AFTER
#   - seeing requires showing: the viewer must be shown too (and have had their
#     account for MIN_ACCOUNT_AGE), or they see nobody
#   - distances are between city centres and only ever shown bucketed
#     ("Same city", "~40 km", "Same country"); we never hold anyone's coordinates
#   - small towns don't give people away: a member in a town under
#     SMALL_TOWN_POPULATION is shown as "near" the nearest big city within
#     GROUP_RADIUS_KM, and no place (a dot, an "In <city>" section, a city label)
#     is shown with fewer than MIN_PER_PLACE members; those fold into the wider
#     "Within 50 km" section, a region or the country instead.
class BreathersAround
  NEAR_KM = 50
  LIST_LIMIT = 60
  SMALL_TOWN_POPULATION = 50_000
  GROUP_RADIUS_KM = 60
  MIN_PER_PLACE = 3
  # The city picker only says "· 7 breathers" for cities this close to your own.
  COUNT_RADIUS_KM = 100
  INACTIVE_AFTER = 60.days
  MIN_ACCOUNT_AGE = 7.days
  BUCKETS = %i[same_city near country].freeze

  # Where a member is shown: their own city, or "near" a big city for a small town.
  Place = Struct.new(:city, :grouped, keyword_init: true) do
    def name = grouped ? "near #{city.name}" : city.name
    # The wider area used when a place has too few members to name it.
    def region = city.admin1_name.presence || city.country_name
  end

  # folded: their place has too few members to name, so only the region shows.
  # same_city: really in the viewer's own (not small-town) city.
  Person = Struct.new(:user, :place, :bucket, :distance_km, :folded, :same_city, keyword_init: true) do
    def where = folded ? place.region : place.name
    # The area to mention in a hello ("around Akure", "around Ondo State").
    def area = folded ? place.region : place.city.name

    def distance_label
      return BreathersAround.distance_label(bucket, distance_km) unless folded

      bucket == :country ? "Same country" : "Within #{NEAR_KM} km"
    end
  end
  Section = Struct.new(:key, :title, :people, keyword_init: true)
  Dot = Struct.new(:name, :lat, :lng, :count, :mine, :near, :country, :distance, keyword_init: true)

  attr_reader :viewer, :city

  def initialize(viewer)
    @viewer = viewer
    @city = viewer&.profile&.city
    @places = {}
  end

  # "Same city", "~40 km" (to the nearest 10, never less than 10), "Same country".
  def self.distance_label(bucket, km)
    case bucket
    when :same_city then "Same city"
    when :near then "~#{[ (km.to_f / 10).round * 10, 10 ].max} km"
    else "Same country"
    end
  end

  # May this member use the page at all? (Under-18s can't.)
  def allowed? = viewer.present? && !viewer.profile&.minor?

  # New accounts wait a week (admins can always look, for testing).
  def account_old_enough?
    return false unless viewer
    return true if viewer.admin? || viewer.super_admin?

    viewer.created_at.present? && viewer.created_at <= MIN_ACCOUNT_AGE.ago
  end

  # Is the viewer findable themselves? (Seeing requires showing.)
  def showing?
    profile = viewer&.profile
    profile.present? && profile.show_in_nearby? && profile.city_id.present? && !profile.city_shown_to_only_me?
  end

  def can_see? = city.present? && allowed? && account_old_enough? && showing?

  # Everyone this viewer may find, anywhere (a Profile scope).
  def visible_profiles
    connections = connection_ids
    since = INACTIVE_AFTER.ago
    scope = Profile.joins(:user).where(show_in_nearby: true).where.not(city_id: nil)
                   .merge(User.active)
                   .where("users.last_seen_at >= :since OR (users.last_seen_at IS NULL AND users.created_at >= :since)", since: since)
                   .where.not(user_id: [ viewer.id, *viewer.blocked_user_ids ])
                   .adults_or_unknown
    shown = Profile.where(city_visibility: :everyone)
    shown = shown.or(Profile.where(city_visibility: :connections, user_id: connections)) if connections.any?
    scope.merge(shown)
  end

  # Where the viewer's own city is shown (a big city, or near one).
  def my_place = city && place_for(city)

  # The page's three sections, filtered (mentoring:, industry:, my_rooms:).
  def sections(filters = {})
    return [] unless can_see?

    people = nearby_people(filters)
    same = people.select { |p| p.bucket == :same_city }
    around = my_place.grouped || same.any? { |p| p.place.grouped }
    [
      Section.new(key: :same_city, title: "In #{'and around ' if around}#{my_place.city.name}", people: same),
      Section.new(key: :near, title: "Within #{NEAR_KM} km", people: people.select { |p| p.bucket == :near }),
      Section.new(key: :country, title: "Elsewhere in #{city.country_name}", people: people.select { |p| p.bucket == :country })
    ]
  end

  # One dot per place (never per person) with how many are there, for the map,
  # worldwide; each says whether it's near the viewer or in their country so the
  # map's "Near me · Country · World" chips can zoom without another request.
  # Places with fewer than MIN_PER_PLACE members fold into a dot for their region
  # (or, if that's still too few, their country) at the area's centre.
  def map_dots(filters = {})
    return [] unless can_see?

    everyone = place_counts(visible_profiles)
    shown = filters.values.any? ? place_counts(filtered(visible_profiles, filters)) : everyone
    mine = my_place
    dots = []
    regions = Hash.new { |h, k| h[k] = [ 0, 0 ] } # [country, admin1] => [everyone, shown]

    everyone.each do |place_id, total|
      place_city = @place_cities[place_id]
      n = shown[place_id].to_i
      if total >= MIN_PER_PLACE
        dots << city_dot(place_city, n, mine: place_id == mine.city.id) if n.positive? || place_id == mine.city.id
      else
        key = [ place_city.country_code, place_city.admin1_code.to_s ]
        regions[key][0] += total
        regions[key][1] += n
      end
    end
    dots += area_dots(regions)
    unless dots.any?(&:mine)
      dots << Dot.new(name: city.name, lat: city.lat.round(3), lng: city.lng.round(3), count: 0, mine: true,
                      near: true, country: true, distance: nil)
    end
    dots
  end

  # For the feed card: how many live in the viewer's place (or, if that's too few
  # to name it, within 50 km), and, for members who can see, a few faces and how
  # many show they're open to mentoring.
  Preview = Struct.new(:users, :count, :mentoring, :where, keyword_init: true)

  def city_preview(faces: 3)
    none = Preview.new(users: [], count: 0, mentoring: 0, where: nil)
    return none unless city && allowed?

    rows = local_scope(NEAR_KM + GROUP_RADIUS_KM).pluck(:user_id, :city_id)
    places = places_for(rows.map(&:last).uniq)
    mine = my_place
    in_place = rows.select { |_, city_id| places[city_id]&.city&.id == mine.city.id }
    if in_place.size >= MIN_PER_PLACE
      ids = in_place.map(&:first)
      where = "in #{'and around ' if mine.grouped}#{mine.city.name}"
    else
      ids = rows.select { |_, city_id| (p = places[city_id]) && city.distance_km_to(p.city) <= NEAR_KM }.map(&:first)
      where = "within #{NEAR_KM} km of you"
    end
    return none if ids.empty?
    return Preview.new(users: [], count: ids.size, mentoring: 0, where: where) unless can_see?

    face_ids = ids.sort.reverse.first(faces)
    users = User.where(id: face_ids).includes(profile: { avatar_attachment: :blob }).sort_by { |u| face_ids.index(u.id) }
    Preview.new(users: users, count: ids.size, where: where,
                mentoring: filtered(visible_profiles.where(user_id: ids), mentoring: true).count)
  end

  # How many live in the viewer's city or within 50 km (the opt-in screen).
  def count_near
    return 0 unless city && allowed?

    local_scope(NEAR_KM).count
  end

  # "· 7 breathers" for the city picker: only for big cities within
  # COUNT_RADIUS_KM of the viewer's own, only with MIN_PER_PLACE or more, and
  # only for members who can see Breathers around you. { city_id => count }
  def picker_counts(cities)
    return {} unless can_see?

    near = cities.select { |c| c.population >= SMALL_TOWN_POPULATION && c.distance_km_to(city) <= COUNT_RADIUS_KM }
    return {} if near.empty?

    counts = place_counts(local_scope(COUNT_RADIUS_KM + GROUP_RADIUS_KM))
    near.to_h { |c| [ c.id, counts[c.id].to_i ] }.select { |_, n| n >= MIN_PER_PLACE }
  end

  # The most common industries among people the viewer can find nearby (filter pills).
  def top_industries(limit = 2)
    return [] unless can_see?

    region_scope.where.not(industry: [ nil, "" ]).group(:industry).order(Arel.sql("COUNT(*) DESC"), :industry)
                .limit(limit).count.keys
  end

  # Rooms the viewer shares with each of these people ({ user_id => [room names] }).
  def shared_rooms(user_ids)
    mine = RoomMembership.where(user_id: viewer.id).select(:room_id)
    names = Room.where(id: mine).pluck(:id, :name).to_h
    RoomMembership.where(user_id: user_ids, room_id: names.keys).pluck(:user_id, :room_id)
                  .group_by(&:first).transform_values { |pairs| pairs.map { |_, room_id| names[room_id] } }
  end

  # { city_id => Place } (a small town grouped under the nearest big city).
  def places_for(city_ids)
    @place_cities ||= {}
    missing = city_ids.compact.uniq - @places.keys
    if missing.any?
      cities = City.where(id: missing).index_by(&:id)
      small = cities.values.select { |c| c.population < SMALL_TOWN_POPULATION }.map(&:id)
      big_ids = nearest_big_cities(small)
      bigs = City.where(id: big_ids.values.uniq).index_by(&:id)
      cities.each do |id, c|
        big = bigs[big_ids[id]]
        @places[id] = big ? Place.new(city: big, grouped: true) : Place.new(city: c, grouped: false)
        @place_cities[@places[id].city.id] = @places[id].city
      end
    end
    @places.slice(*city_ids)
  end

  def place_for(city) = places_for([ city.id ])[city.id]

  private

  def connection_ids = @connection_ids ||= viewer.connection_ids

  def distance_sql = City.distance_sql(city.lat, city.lng)

  # Members within km of the viewer's city.
  def local_scope(km)
    visible_profiles.joins(:city).where("profiles.city_id = :id OR #{City::DISTANCE_SQL} <= :km",
                                        id: city.id, km: km, lat: city.lat, lng: city.lng)
  end

  # Same city, near it (wide enough to catch small towns grouped near it), or in the same country.
  def region_scope
    visible_profiles.joins(:city)
                    .where("profiles.city_id = :id OR cities.country_code = :cc OR #{City::DISTANCE_SQL} <= :near",
                           id: city.id, cc: city.country_code, near: NEAR_KM + GROUP_RADIUS_KM, lat: city.lat, lng: city.lng)
  end

  # { place city id => members } for a Profile scope.
  def place_counts(scope)
    counts = scope.group("profiles.city_id").count
    places = places_for(counts.keys)
    counts.each_with_object(Hash.new(0)) do |(city_id, n), sums|
      place = places[city_id] or next
      sums[place.city.id] += n
    end
  end

  # { small town id => nearest city id with SMALL_TOWN_POPULATION+ within GROUP_RADIUS_KM }
  def nearest_big_cities(small_ids)
    return {} if small_ids.empty?

    pair_km = "(#{City::EARTH_RADIUS_KM} * 2 * ASIN(SQRT(LEAST(1.0, POWER(SIN(RADIANS(b.lat - s.lat) / 2), 2) + " \
              "COS(RADIANS(s.lat)) * COS(RADIANS(b.lat)) * POWER(SIN(RADIANS(b.lng - s.lng) / 2), 2)))))"
    dlng = ":dlat / GREATEST(COS(RADIANS(s.lat)), 0.05)"
    sql = City.sanitize_sql_array([ <<~SQL.squish, { ids: small_ids, min: SMALL_TOWN_POPULATION, km: GROUP_RADIUS_KM, dlat: GROUP_RADIUS_KM / 110.0 + 0.01 } ])
      SELECT s.id, near.id FROM cities s
      CROSS JOIN LATERAL (
        SELECT b.id FROM cities b
        WHERE b.population >= :min AND b.id <> s.id
          AND b.lat BETWEEN s.lat - :dlat AND s.lat + :dlat
          AND b.lng BETWEEN s.lng - #{dlng} AND s.lng + #{dlng}
          AND #{pair_km} <= :km
        ORDER BY #{pair_km}, b.population DESC LIMIT 1
      ) near
      WHERE s.id IN (:ids)
    SQL
    City.connection.select_rows(sql).to_h { |small, big| [ small.to_i, big.to_i ] }
  end

  def city_dot(place_city, count, mine:)
    km = place_city.id == city.id ? 0 : place_city.distance_km_to(city)
    near = mine || km <= NEAR_KM
    Dot.new(name: place_city.name, lat: place_city.lat.round(3), lng: place_city.lng.round(3), count: count, mine: mine,
            near: near, country: place_city.country_code == city.country_code,
            distance: (self.class.distance_label(:near, km) if !mine && near))
  end

  # Folded places: a dot per region with MIN_PER_PLACE+, then per country for the rest.
  def area_dots(regions)
    return [] if regions.empty?

    countries = Hash.new { |h, k| h[k] = [ 0, 0 ] }
    keep = regions.select do |(cc, _), (total, n)|
      next true if total >= MIN_PER_PLACE

      countries[cc][0] += total
      countries[cc][1] += n
      false
    end
    countries = countries.select { |_, (total, _)| total >= MIN_PER_PLACE }
    dots = []
    if keep.any?
      centres = City.where(country_code: keep.keys.map(&:first).uniq).group(:country_code, :admin1_code)
                    .pluck(:country_code, :admin1_code, *centre_columns, Arel.sql("MAX(admin1_name)"), Arel.sql("MAX(country_name)"))
                    .index_by { |cc, a1, *| [ cc, a1.to_s ] }
      keep.each do |key, (_, n)|
        next unless n.positive? && (row = centres[key])

        dots << area_dot(row[4].presence || row[5], row[2], row[3], key.first, n)
      end
    end
    if countries.any?
      City.where(country_code: countries.keys).group(:country_code)
          .pluck(:country_code, *centre_columns, Arel.sql("MAX(country_name)")).each do |cc, lat, lng, name|
        n = countries[cc][1]
        dots << area_dot(name, lat, lng, cc, n) if n.positive?
      end
    end
    dots
  end

  # A population-weighted centre, so a region's dot sits where people live, not on anyone's town.
  def centre_columns
    [ Arel.sql("SUM(lat * (population + 1)) / SUM(population + 1)"), Arel.sql("SUM(lng * (population + 1)) / SUM(population + 1)") ]
  end

  def area_dot(name, lat, lng, country_code, count)
    Dot.new(name: name, lat: lat.to_f.round(2), lng: lng.to_f.round(2), count: count, mine: false,
            near: false, country: country_code == city.country_code, distance: nil)
  end

  def filtered(scope, filters)
    if filters[:mentoring]
      # "Open to mentoring" counts only where the member shows it to this viewer.
      open = Profile.where(open_to_visibility: :everyone)
      open = open.or(Profile.where(open_to_visibility: :connections, user_id: connection_ids)) if connection_ids.any?
      scope = scope.where("'mentoring' = ANY(profiles.open_to)").merge(open)
    end
    scope = scope.where(industry: filters[:industry]) if filters[:industry].present?
    if filters[:my_rooms]
      # People in any room the viewer is in.
      scope = scope.where(user_id: RoomMembership.where(room_id: RoomMembership.where(user_id: viewer.id).select(:room_id))
                                                 .select(:user_id))
    end
    scope
  end

  def nearby_people(filters)
    rows = filtered(region_scope, filters)
             .select("profiles.user_id, profiles.city_id, #{distance_sql} AS distance_km")
             .order(Arel.sql("(profiles.city_id = #{city.id.to_i}) DESC, distance_km ASC, profiles.user_id DESC"))
             .limit(LIST_LIMIT)
             .map { |r| [ r.user_id, r.city_id ] }

    # Whether a place has enough members to name is judged on everyone, not the filter.
    counts = place_counts(region_scope)
    places = places_for(rows.map(&:last).uniq)
    users = User.where(id: rows.map(&:first))
                .includes(:experiences, profile: { avatar_attachment: :blob }).index_by(&:id)
    mine = my_place
    people = rows.filter_map do |user_id, city_id|
      user = users[user_id]
      place = places[city_id]
      next unless user && place

      folded = counts[place.city.id] < MIN_PER_PLACE
      km = place.city.id == mine.city.id ? 0.0 : city.distance_km_to(place.city)
      bucket = if place.city.id == mine.city.id then (folded ? :near : :same_city)
      elsif km <= NEAR_KM then :near
      elsif place.city.country_code == city.country_code then :country
      end
      next unless bucket

      Person.new(user: user, place: place, bucket: bucket, distance_km: km, folded: folded,
                 same_city: !folded && !place.grouped && city_id == city.id)
    end
    # Folded people sort as if at the edge of their section, so the order hints at nothing.
    people.sort_by { |p| [ BUCKETS.index(p.bucket), p.folded ? NEAR_KM : p.distance_km, -p.user.id ] }
  end
end

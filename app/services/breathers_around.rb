# frozen_string_literal: true

# "Breathers around you": members who chose to be found, in the viewer's city,
# within 50 km of it, then elsewhere in their country.
#
# Privacy rules (all enforced here, in SQL, for every list, count and map dot):
#   - only members who turned on "Show me in Breathers around you" and have a city
#   - their city visibility allows this viewer (everyone, or connections only)
#   - never the viewer, blocked people (either way), deactivated accounts or under-18s
#   - distances are between city centres and only ever shown bucketed
#     ("Same city", "~40 km", "Same country"); we never hold anyone's coordinates.
class BreathersAround
  NEAR_KM = 50
  LIST_LIMIT = 60

  Person = Struct.new(:user, :city, :bucket, :distance_km, keyword_init: true) do
    def distance_label = BreathersAround.distance_label(bucket, distance_km)
  end
  Section = Struct.new(:key, :title, :people, keyword_init: true)
  Dot = Struct.new(:name, :lat, :lng, :count, :mine, :near, :country, :distance, keyword_init: true)

  attr_reader :viewer, :city

  def initialize(viewer)
    @viewer = viewer
    @city = viewer&.profile&.city
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

  # Everyone this viewer may find, anywhere (a Profile scope).
  def visible_profiles
    connections = connection_ids
    scope = Profile.joins(:user).where(show_in_nearby: true).where.not(city_id: nil)
                   .merge(User.active)
                   .where.not(user_id: [ viewer.id, *viewer.blocked_user_ids ])
                   .adults_or_unknown
    shown = Profile.where(city_visibility: :everyone)
    shown = shown.or(Profile.where(city_visibility: :connections, user_id: connections)) if connections.any?
    scope.merge(shown)
  end

  # How many findable members live in the viewer's city (the feed card).
  def count_in_my_city
    return 0 unless city && allowed?

    visible_profiles.where(city_id: city.id).count
  end

  # The page's three sections, filtered (mentoring:, industry:, my_rooms:).
  def sections(filters = {})
    return [] unless city

    people = nearby_people(filters)
    [
      Section.new(key: :same_city, title: "In #{city.name}", people: people.select { |p| p.bucket == :same_city }),
      Section.new(key: :near, title: "Within #{NEAR_KM} km", people: people.select { |p| p.bucket == :near }),
      Section.new(key: :country, title: "Elsewhere in #{city.country_name}", people: people.select { |p| p.bucket == :country })
    ]
  end

  # One dot per city (never per person) with how many are there, for the map,
  # worldwide; each says whether it's near the viewer or in their country so the
  # map's "Near me · Country · World" chips can zoom without another request.
  def map_dots(filters = {})
    return [] unless city

    counts = filtered(visible_profiles, filters).group(:city_id).count
    cities = City.where(id: counts.keys | [ city.id ]).index_by(&:id)
    counts[city.id] ||= 0
    counts.filter_map do |city_id, n|
      c = cities[city_id] or next
      km = c.distance_km_to(city)
      Dot.new(name: c.name, lat: c.lat.round(3), lng: c.lng.round(3), count: n, mine: city_id == city.id,
              near: city_id == city.id || km <= NEAR_KM, country: c.country_code == city.country_code,
              distance: (self.class.distance_label(:near, km) if city_id != city.id && km <= NEAR_KM))
    end
  end

  # For the feed card: a few faces from the viewer's city, how many in all, and
  # how many show they're open to mentoring.
  Preview = Struct.new(:users, :count, :mentoring, keyword_init: true)

  def city_preview(faces: 3)
    return Preview.new(users: [], count: 0, mentoring: 0) unless city && allowed?

    mine = visible_profiles.where(city_id: city.id)
    count = mine.count
    return Preview.new(users: [], count: 0, mentoring: 0) if count.zero?

    ids = mine.order(user_id: :desc).limit(faces).pluck(:user_id)
    users = User.where(id: ids).includes(profile: { avatar_attachment: :blob }).sort_by { |u| ids.index(u.id) }
    Preview.new(users: users, count: count, mentoring: filtered(mine, mentoring: true).count)
  end

  # How many live in the viewer's city or within 50 km (the opt-in screen).
  def count_near
    return 0 unless city && allowed?

    visible_profiles.joins(:city).where("profiles.city_id = :id OR #{City::DISTANCE_SQL} <= :near",
                                        id: city.id, near: NEAR_KM, lat: city.lat, lng: city.lng).count
  end

  # The most common industries among people the viewer can find nearby (filter pills).
  def top_industries(limit = 2)
    return [] unless city

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

  private

  def connection_ids = @connection_ids ||= viewer.connection_ids

  def distance_sql = City.distance_sql(city.lat, city.lng)

  # Same city, near it, or in the same country.
  def region_scope
    visible_profiles.joins(:city)
                    .where("profiles.city_id = :id OR cities.country_code = :cc OR #{City::DISTANCE_SQL} <= :near",
                           id: city.id, cc: city.country_code, near: NEAR_KM, lat: city.lat, lng: city.lng)
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
             .map { |r| [ r.user_id, r.city_id, r.distance_km.to_f ] }

    users = User.where(id: rows.map(&:first))
                .includes(:experiences, profile: { avatar_attachment: :blob }).index_by(&:id)
    cities = City.where(id: rows.map { |r| r[1] }).index_by(&:id)
    rows.filter_map do |user_id, city_id, km|
      next unless users[user_id]

      bucket = if city_id == city.id then :same_city
      elsif km <= NEAR_KM then :near
      else :country
      end
      Person.new(user: users[user_id], city: cities[city_id], bucket: bucket, distance_km: km)
    end
  end
end

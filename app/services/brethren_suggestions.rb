# frozen_string_literal: true

# "Brethren you may know" (LinkedIn's "People you may know").
#
# Scores everyone the viewer isn't already connected to by what they share,
# strongest first, and keeps the best reason to show on the card:
#   same assembly · mutual brethren · same organisation · same profession ·
#   shared skills · same city · same rooms
# Only public information is used (the private Brethren Card is never read).
class BrethrenSuggestions
  Suggestion = Struct.new(:user, :score, :reason, :kind, :mutuals, keyword_init: true)

  WEIGHTS = { assembly: 40, organization: 25, profession: 15, mutual: 10, city: 8, room: 3, skill: 4 }.freeze
  CAPS = { mutual: 50, room: 12, skill: 12 }.freeze
  # Each source (same assembly, city, skills, work, rooms, mutuals) reads at
  # most this many candidates, newest members first, so a big church or city
  # can't make a feed load pull thousands of rows.
  SOURCE_CAP = 500
  # Scored candidates are cached per member; follows, connection changes and
  # profile edits clear it (BrethrenSuggestions.expire). Dismissals, requests
  # and blocks are re-checked on every read, so they apply at once.
  CACHE_TTL = 3.hours
  CACHED_CANDIDATES = 100
  # Locations that say nothing about where someone is.
  VAGUE_CITIES = %w[online remote worldwide everywhere global earth].freeze

  def self.for(user, limit: 10) = new(user).call(limit)

  def self.cache_key(user_id) = "brethren_suggestions/v1/#{user_id}"

  def self.expire(*user_ids)
    user_ids.flatten.compact.uniq.each { |id| Rails.cache.delete(cache_key(id)) }
  end

  def initialize(user)
    @user = user
    @scores = Hash.new(0)
    @reasons = Hash.new { |h, k| h[k] = [] } # [weight, text, kind]
    @mutual_ids = {} # suggested id => ids of my connections they know
  end

  def call(limit)
    return [] unless @user

    ranked = Rails.cache.fetch(self.class.cache_key(@user.id), expires_in: CACHE_TTL) { rank }
    excluded = excluded_ids.to_set
    picks = ranked.reject { |c| excluded.include?(c[:id]) }.first(limit)
    ids = picks.map { |c| c[:id] }

    users = User.active.where(id: ids).includes(:experiences, profile: { avatar_attachment: :blob }).index_by(&:id)
    faces = User.where(id: picks.flat_map { |c| c[:mutual_ids] }.uniq)
                .includes(profile: { avatar_attachment: :blob }).index_by(&:id)
    picks.filter_map do |c|
      next unless users[c[:id]]

      mutuals = c[:mutual_ids].filter_map { |mid| faces[mid] }
      Suggestion.new(user: users[c[:id]], score: c[:score], reason: c[:reason], kind: c[:kind], mutuals: mutuals)
    end
  end

  private

  # The best CACHED_CANDIDATES as plain hashes (cache-friendly), strongest first.
  def rank
    add_assembly
    add_mutuals
    add_work
    add_skills
    add_city
    add_rooms

    ids = (@scores.keys - excluded_ids).sort_by { |id| -@scores[id] }.first(CACHED_CANDIDATES)
    ids.map do |id|
      _points, reason, kind = @reasons[id].max_by(&:first)
      { id: id, score: @scores[id], reason: reason, kind: kind, mutual_ids: @mutual_ids[id].to_a.first(3) }
    end
  end

  def profile = @user.profile

  # Candidate profiles/rows minus people already excluded, newest first, capped.
  def capped(scope, user_column = :user_id)
    scope.where.not(user_column => excluded_ids).order(user_column => :desc).limit(SOURCE_CAP)
  end

  def bump(ids_with_counts, kind, &reason)
    ids_with_counts.each do |id, count|
      next if id == @user.id

      points = WEIGHTS[kind] * count
      points = [ points, CAPS[kind] ].min if CAPS[kind]
      @scores[id] += points
      @reasons[id] << [ points, reason.call(count), kind ]
    end
  end

  def add_assembly
    return if profile&.assembly_key.blank?

    ids = capped(Profile.where(assembly_key: profile.assembly_key)).pluck(:user_id)
    bump(ids.index_with(1), :assembly) { "Also at #{profile.assembly}" }
  end

  def add_mutuals
    mine = my_connection_ids
    return if mine.empty?

    accepted = ConnectionRequest.accepted
    # [their id, my connection who knows them]
    pairs = capped(accepted.where(sender_id: mine), :receiver_id).limit(SOURCE_CAP * 4).pluck(:receiver_id, :sender_id) +
            capped(accepted.where(receiver_id: mine), :sender_id).limit(SOURCE_CAP * 4).pluck(:sender_id, :receiver_id)
    @mutual_ids = pairs.group_by(&:first).transform_values { |list| list.map(&:last).uniq }
    bump(@mutual_ids.transform_values(&:size), :mutual) { |n| "#{n} mutual #{n == 1 ? 'brother or sister' : 'brethren'}" }
  end

  def add_work
    roles = @user.experiences.to_a
    org_keys = roles.filter_map(&:organization_key).uniq
    title_keys = roles.filter_map(&:title_key).uniq

    if org_keys.any?
      by_org = capped(Experience.where(organization_key: org_keys)).pluck(:user_id, :organization).uniq(&:first)
      by_org.each { |id, org| bump({ id => 1 }, :organization) { "Also at #{org}" } }
    end
    return if title_keys.empty?

    capped(Experience.where(title_key: title_keys)).pluck(:user_id, :title).uniq(&:first).each do |id, title|
      bump({ id => 1 }, :profession) { "Fellow #{title.downcase}" }
    end
  end

  def add_skills
    skills = profile&.skills.to_a.map(&:downcase)
    return if skills.empty?

    capped(Profile.where("skills && ARRAY[?]::varchar[]", profile.skills)).pluck(:user_id, :skills).each do |id, theirs|
      shared = theirs.map(&:downcase) & skills
      bump({ id => shared.size }, :skill) { "Also into #{theirs.find { |s| s.downcase == shared.first }}" } if shared.any?
    end
  end

  def add_city
    key = profile&.city_key
    return if key.blank? || VAGUE_CITIES.include?(key)

    city = profile.location.to_s.split(",").first.to_s.strip
    bump(capped(Profile.where(city_key: key)).pluck(:user_id).index_with(1), :city) { "Also in #{city}" }
  end

  def add_rooms
    room_ids = RoomMembership.where(user_id: @user.id).pluck(:room_id)
    return if room_ids.empty?

    shared = capped(RoomMembership.where(room_id: room_ids)).limit(SOURCE_CAP * 4).pluck(:user_id, :room_id)
                           .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
    names = Room.where(id: room_ids).pluck(:id, :name).to_h
    shared.each do |id, rooms|
      bump({ id => rooms.size }, :room) { |n| n == 1 ? "Both in #{names[rooms.first]}" : "In #{n} of the same rooms" }
    end
  end

  def my_connection_ids = @my_connection_ids ||= @user.connection_ids

  # Already connected, asked, dismissed, blocked, or yourself.
  def excluded_ids
    @excluded_ids ||= begin
      pending = ConnectionRequest.pending
      ([ @user.id ] + my_connection_ids +
        pending.where(sender_id: @user.id).pluck(:receiver_id) + pending.where(receiver_id: @user.id).pluck(:sender_id) +
        @user.suggestion_dismissals.pluck(:dismissed_user_id) +
        MessageBlock.where(blocker_id: @user.id).pluck(:blocked_id) +
        MessageBlock.where(blocked_id: @user.id).pluck(:blocker_id)).uniq
    end
  end
end

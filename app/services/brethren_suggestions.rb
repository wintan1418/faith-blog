# frozen_string_literal: true

# "Brethren you may know" (LinkedIn's "People you may know").
#
# Scores everyone the viewer isn't already connected to by what they share,
# strongest first, and keeps the best reason to show on the card:
#   same assembly · mutual brethren · same organisation · same profession ·
#   shared skills · same city · same rooms
# Only public information is used (the private Brethren Card is never read).
class BrethrenSuggestions
  Suggestion = Struct.new(:user, :score, :reason, keyword_init: true)

  WEIGHTS = { assembly: 40, organization: 25, profession: 15, mutual: 10, city: 8, room: 3, skill: 4 }.freeze
  CAPS = { mutual: 50, room: 12, skill: 12 }.freeze
  # Locations that say nothing about where someone is.
  VAGUE_CITIES = %w[online remote worldwide everywhere global earth].freeze

  def self.for(user, limit: 10) = new(user).call(limit)

  def initialize(user)
    @user = user
    @scores = Hash.new(0)
    @reasons = Hash.new { |h, k| h[k] = [] } # [weight, text]
  end

  def call(limit)
    return [] unless @user

    add_assembly
    add_mutuals
    add_work
    add_skills
    add_city
    add_rooms

    ids = (@scores.keys - excluded_ids).sort_by { |id| -@scores[id] }.first(limit)
    users = User.active.where(id: ids).includes(profile: { avatar_attachment: :blob }).index_by(&:id)
    ids.filter_map do |id|
      next unless users[id]

      Suggestion.new(user: users[id], score: @scores[id], reason: @reasons[id].max_by(&:first)&.last)
    end
  end

  private

  def profile = @user.profile

  def bump(ids_with_counts, kind, &reason)
    ids_with_counts.each do |id, count|
      next if id == @user.id

      points = WEIGHTS[kind] * count
      points = [ points, CAPS[kind] ].min if CAPS[kind]
      @scores[id] += points
      @reasons[id] << [ points, reason.call(count) ]
    end
  end

  def add_assembly
    return if profile&.assembly_key.blank?

    ids = Profile.where(assembly_key: profile.assembly_key).pluck(:user_id)
    bump(ids.index_with(1), :assembly) { "Also at #{profile.assembly}" }
  end

  def add_mutuals
    mine = my_connection_ids
    return if mine.empty?

    accepted = ConnectionRequest.accepted
    theirs = accepted.where(sender_id: mine).pluck(:receiver_id) + accepted.where(receiver_id: mine).pluck(:sender_id)
    bump(theirs.tally, :mutual) { |n| "#{n} mutual #{n == 1 ? 'brother or sister' : 'brethren'}" }
  end

  def add_work
    roles = @user.experiences.to_a
    org_keys = roles.filter_map(&:organization_key).uniq
    title_keys = roles.filter_map(&:title_key).uniq

    if org_keys.any?
      by_org = Experience.where(organization_key: org_keys).pluck(:user_id, :organization).uniq(&:first)
      by_org.each { |id, org| bump({ id => 1 }, :organization) { "Also at #{org}" } }
    end
    return if title_keys.empty?

    Experience.where(title_key: title_keys).pluck(:user_id, :title).uniq(&:first).each do |id, title|
      bump({ id => 1 }, :profession) { "Fellow #{title.downcase}" }
    end
  end

  def add_skills
    skills = profile&.skills.to_a.map(&:downcase)
    return if skills.empty?

    Profile.where("skills && ARRAY[?]::varchar[]", profile.skills).pluck(:user_id, :skills).each do |id, theirs|
      shared = theirs.map(&:downcase) & skills
      bump({ id => shared.size }, :skill) { "Also into #{theirs.find { |s| s.downcase == shared.first }}" } if shared.any?
    end
  end

  def add_city
    key = profile&.city_key
    return if key.blank? || VAGUE_CITIES.include?(key)

    city = profile.location.to_s.split(",").first.to_s.strip
    bump(Profile.where(city_key: key).pluck(:user_id).index_with(1), :city) { "Also in #{city}" }
  end

  def add_rooms
    room_ids = RoomMembership.where(user_id: @user.id).pluck(:room_id)
    return if room_ids.empty?

    shared = RoomMembership.where(room_id: room_ids).where.not(user_id: @user.id).pluck(:user_id, :room_id)
                           .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
    names = Room.where(id: room_ids).pluck(:id, :name).to_h
    shared.each do |id, rooms|
      bump({ id => rooms.size }, :room) { |n| n == 1 ? "Both in #{names[rooms.first]}" : "In #{n} of the same rooms" }
    end
  end

  def my_connection_ids = @my_connection_ids ||= @user.connection_ids

  # Already connected, asked, dismissed, blocked, or yourself.
  def excluded_ids
    pending = ConnectionRequest.pending
    [ @user.id ] + my_connection_ids +
      pending.where(sender_id: @user.id).pluck(:receiver_id) + pending.where(receiver_id: @user.id).pluck(:sender_id) +
      @user.suggestion_dismissals.pluck(:dismissed_user_id) +
      MessageBlock.where(blocker_id: @user.id).pluck(:blocked_id) + MessageBlock.where(blocked_id: @user.id).pluck(:blocker_id)
  end
end

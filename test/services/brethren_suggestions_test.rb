# frozen_string_literal: true

require "test_helper"

class BrethrenSuggestionsTest < ActiveSupport::TestCase
  def make_user(name, **profile)
    User.create!(username: name, email: "#{name}@example.com", password: "Pw-#{SecureRandom.hex(8)}").tap do |u|
      u.profile.update!(profile) if profile.any?
    end
  end

  def connect(a, b, status: :accepted)
    ConnectionRequest.new(sender: a, receiver: b, status: status).save!(validate: false)
  end

  def suggested(user) = BrethrenSuggestions.for(user, limit: 20)

  setup { @me = make_user("viewer", assembly: "R.C.C.G Jubilee Parish", location: "Lagos, Nigeria") }

  test "same assembly (however it's typed) leads, with the reason" do
    church = make_user("churchmate", assembly: "rccg jubilee parish")
    city = make_user("neighbour", location: "Lagos")

    top = suggested(@me).first
    assert_equal church, top.user
    assert_equal "Also at R.C.C.G Jubilee Parish", top.reason
    assert_includes suggested(@me).map(&:user), city
  end

  test "mutual connections, same organisation and profession count" do
    friend = make_user("friend")
    friend_of_friend = make_user("fof")
    connect(@me, friend)
    connect(friend, friend_of_friend)
    @me.experiences.create!(title: "Nurse", organization: "LUTH", start_month: "2020-01", current: true)
    colleague = make_user("colleague")
    colleague.experiences.create!(title: "Doctor", organization: "L.U.T.H.", start_month: "2021-01", current: true)
    nurse = make_user("nurse")
    nurse.experiences.create!(title: "nurse", organization: "Reddington", start_month: "2021-01", current: true)

    reasons = suggested(@me).to_h { |s| [ s.user.username, s.reason ] }
    assert_equal "1 mutual brother or sister", reasons["fof"]
    assert_equal "Also at L.U.T.H.", reasons["colleague"]
    assert_equal "Fellow nurse", reasons["nurse"]

    fof = suggested(@me).find { |s| s.user == friend_of_friend }
    assert_equal :mutual, fof.kind
    assert_equal [ friend ], fof.mutuals
    assert_equal :organization, suggested(@me).find { |s| s.user == colleague }.kind
  end

  test "never suggests connections, pending requests, dismissed or blocked people" do
    connected = make_user("connected", assembly: "RCCG Jubilee Parish")
    asked = make_user("asked", assembly: "RCCG Jubilee Parish")
    dismissed = make_user("dismissed", assembly: "RCCG Jubilee Parish")
    blocked = make_user("blocked", assembly: "RCCG Jubilee Parish")
    connect(@me, connected)
    connect(@me, asked, status: :pending)
    @me.suggestion_dismissals.create!(dismissed_user: dismissed)
    MessageBlock.create!(blocker: blocked, blocked: @me)

    names = suggested(@me).map { |s| s.user.username }
    assert_empty names & %w[connected asked dismissed blocked viewer]
  end

  test "vague locations like 'Online' don't match" do
    @me.profile.update!(location: "Online", assembly: nil)
    make_user("elsewhere", location: "Online")

    assert_empty suggested(@me)
  end

  test "deleting an account that was dismissed still works" do
    dismissed = make_user("gone")
    @me.suggestion_dismissals.create!(dismissed_user: dismissed)

    assert_difference -> { User.count }, -1 do
      dismissed.destroy!
    end
  end

  test "each source reads at most SOURCE_CAP candidates, newest members first" do
    church = Array.new(4) { |i| make_user("member#{i}", assembly: "RCCG Jubilee Parish") }
    original = BrethrenSuggestions::SOURCE_CAP
    silence_warnings { BrethrenSuggestions.const_set(:SOURCE_CAP, 2) }

    names = suggested(@me).map { |s| s.user.username }
    assert_equal church.last(2).map(&:username).sort, names.sort
  ensure
    silence_warnings { BrethrenSuggestions.const_set(:SOURCE_CAP, original) } if original
  end

  test "suggestions are cached per member; connecting clears it, dismissals apply at once" do
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    a = make_user("church_a", assembly: "RCCG Jubilee Parish")
    b = make_user("church_b", assembly: "RCCG Jubilee Parish")
    assert_equal %w[church_a church_b], suggested(@me).map { |s| s.user.username }.sort

    late = make_user("church_late", assembly: "RCCG Jubilee Parish")
    refute_includes suggested(@me).map(&:user), late, "served from cache"

    @me.suggestion_dismissals.create!(dismissed_user: a)
    refute_includes suggested(@me).map(&:user), a, "dismissal applies without waiting for the cache"

    connect(@me, b)
    names = suggested(@me).map { |s| s.user.username }
    assert_includes names, "church_late", "a new connection clears the cache"
    refute_includes names, "church_b"
  ensure
    Rails.cache = original_cache
  end
end

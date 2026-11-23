# frozen_string_literal: true

require "test_helper"

class BreathersAroundServiceTest < ActiveSupport::TestCase
  test "distance labels are bucketed and never finer than 10 km" do
    assert_equal "Same city", BreathersAround.distance_label(:same_city, 0)
    assert_equal "~10 km", BreathersAround.distance_label(:near, 3.2)
    assert_equal "~40 km", BreathersAround.distance_label(:near, 43.7)
    assert_equal "~50 km", BreathersAround.distance_label(:near, 46)
    assert_equal "Same country", BreathersAround.distance_label(:country, 217)
  end

  test "nearby members boost Brethren you may know, only when they opted in and show their city" do
    me = create_member("viewer_me")
    me.profile.update!(city: cities(:akure))
    near = create_member("near_owo")
    near.profile.update!(city: cities(:owo), show_in_nearby: true)
    shy = create_member("shy_owo")
    shy.profile.update!(city: cities(:owo))
    private_one = create_member("private_owo")
    private_one.profile.update!(city: cities(:owo), show_in_nearby: true, city_visibility: :connections)

    picks = BrethrenSuggestions.for(me).to_h { |s| [ s.user.username, s ] }
    assert_equal "Near you, in Owo", picks["near_owo"].reason
    assert_equal :nearby, picks["near_owo"].kind
    refute picks.key?("shy_owo")
    refute picks.key?("private_owo")
  end

  test "same-city suggestions skip cities kept private" do
    me = create_member("viewer_me2")
    me.profile.update!(city: cities(:lagos))
    create_member("public_lagos").profile.update!(city: cities(:lagos))
    create_member("hidden_lagos").profile.update!(city: cities(:lagos), city_visibility: :only_me)

    names = BrethrenSuggestions.for(me).map { |s| s.user.username }
    assert_includes names, "public_lagos"
    refute_includes names, "hidden_lagos"
  end
end

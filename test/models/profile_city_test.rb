# frozen_string_literal: true

require "test_helper"

class ProfileCityTest < ActiveSupport::TestCase
  setup { @profile = create_member("placed").profile }

  test "picking a city writes the location text and its match key" do
    @profile.update!(city: cities(:akure))
    assert_equal "Akure, Ondo, Nigeria", @profile.location
    assert_equal "akure", @profile.city_key
  end

  test "typing a location finds its city; unclear text keeps the text and no city" do
    @profile.update!(location: "akure, nigeria")
    assert_equal cities(:akure), @profile.city
    assert_equal "Akure, Ondo, Nigeria", @profile.location

    @profile.update!(location: "Online")
    assert_nil @profile.city
    assert_equal "Online", @profile.location
  end

  test "only the city is stored: no coordinates live on a profile" do
    refute(Profile.column_names.any? { |c| c =~ /lat|lng|lon|coord|geo/ })
  end

  test "Breathers around you is off by default and city is visible to everyone" do
    refute @profile.show_in_nearby?
    assert @profile.city_shown_to_everyone?
  end

  test "under-18s can't turn on Breathers around you" do
    year = Date.current.year
    @profile.update!(birth_year: year - 17)
    refute @profile.update(show_in_nearby: true)
    assert_includes @profile.errors[:show_in_nearby].join, "18"

    @profile.update!(birth_year: year - 30, show_in_nearby: true)
    assert @profile.show_in_nearby?
  end

  test "minor? and its SQL twin agree on the edges" do
    today = Date.current
    cases = {
      [ today.year - 18, nil, nil ] => true, # could still be 17 this year
      [ today.year - 19, nil, nil ] => false,
      [ (today - 18.years).year, (today - 18.years).month, (today - 18.years).day ] => false, # 18 today
      [ (today - 18.years + 1.day).year, (today - 18.years + 1.day).month, (today - 18.years + 1.day).day ] => true
    }
    cases.each do |(year, month, day), minor|
      @profile.update_columns(birth_year: year, birth_month: month, birth_day: day)
      assert_equal minor, @profile.reload.minor?, "minor? for #{[ year, month, day ]}"
      assert_equal !minor, Profile.adults_or_unknown.exists?(@profile.id), "SQL for #{[ year, month, day ]}"
    end
  end

  test "city visibility decides who sees the location" do
    me = @profile.user
    friend = create_member("friend")
    stranger = create_member("stranger")
    ConnectionRequest.new(sender: me, receiver: friend, status: :accepted).save!(validate: false)
    @profile.update!(city: cities(:akure))

    assert @profile.city_visible_to?(stranger)
    @profile.update!(city_visibility: :connections)
    assert @profile.city_visible_to?(friend)
    refute @profile.city_visible_to?(stranger)
    refute @profile.city_visible_to?(nil)
    @profile.update!(city_visibility: :only_me)
    refute @profile.city_visible_to?(friend)
    assert @profile.city_visible_to?(me)
  end
end

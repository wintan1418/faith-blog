# frozen_string_literal: true

require "test_helper"

class CityBackfillTest < ActiveSupport::TestCase
  def with_location(name, text)
    create_member(name).profile.tap { |p| p.update_columns(location: text, city_id: nil) }
  end

  test "dry run reports matches and saves nothing; apply saves the clear ones" do
    akure = with_location("loc_a", "Akure, Ondo State, Nigeria")
    state = with_location("loc_b", "Ondo State, Nigeria")
    online = with_location("loc_c", "Online")
    out = StringIO.new

    results = CityBackfill.new(log: out).call
    assert_equal :matched, results.find { |r| r.profile_id == akure.id }.status
    assert_nil akure.reload.city_id
    assert_includes out.string, "dry run"
    assert_includes out.string, "Akure, Ondo, Nigeria"

    CityBackfill.new(apply: true, log: StringIO.new).call
    assert_equal cities(:akure), akure.reload.city
    assert_equal "Akure, Ondo, Nigeria", akure.location
    assert_nil state.reload.city_id
    assert_nil online.reload.city_id
    refute akure.show_in_nearby?, "the backfill never opts anyone in"
  end
end

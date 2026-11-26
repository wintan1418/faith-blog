# frozen_string_literal: true

require "test_helper"

# The built-in calendar: dates worked out correctly, created as drafts, never twice.
class Celebrations::PresetsTest < ActiveSupport::TestCase
  P = Celebrations::Presets

  test "Easter by the computus" do
    { 2019 => [ 4, 21 ], 2024 => [ 3, 31 ], 2025 => [ 4, 20 ], 2026 => [ 4, 5 ], 2027 => [ 3, 28 ], 2038 => [ 4, 25 ], 2285 => [ 3, 22 ] }.each do |year, (m, d)|
      assert_equal Date.new(year, m, d), P.easter(year), "Easter #{year}"
    end
  end

  test "movable days" do
    assert_equal Date.new(2026, 11, 26), P.nth_weekday(2026, 11, 4, 4) # US Thanksgiving
    assert_equal Date.new(2027, 11, 25), P.nth_weekday(2027, 11, 4, 4)
    assert_equal Date.new(2027, 5, 9), P.nth_weekday(2027, 5, 0, 2)   # Mother's Day (US)
    assert_equal Date.new(2027, 6, 20), P.nth_weekday(2027, 6, 0, 3)  # Father's Day
    assert_equal Date.new(2027, 10, 11), P.nth_weekday(2027, 10, 1, 2) # Canadian Thanksgiving

    year = P.for_year(2027).index_by { |p| p.key.delete_suffix("-2027") }
    assert_equal Date.new(2027, 3, 26), year["good-friday"].date
    assert_equal Date.new(2027, 5, 16), year["pentecost"].date
    assert_equal Date.new(2027, 3, 7), year["mothering-sunday"].date
    assert_equal Date.new(2027, 10, 1), year["nigeria-independence"].date
    assert_equal %w[NG], year["nigeria-independence"].country_codes
  end

  test "seeding makes drafts for the next 12 months, once" do
    created = P.seed!(from: Date.new(2026, 11, 26))
    keys = created.map(&:preset_key)
    assert_includes keys, "thanksgiving-us-2026"
    assert_includes keys, "christmas-2026"
    assert_includes keys, "easter-2027"
    assert_not_includes keys, "christmas-2027"
    assert created.all?(&:draft?)

    thanksgiving = Celebration.find_by!(preset_key: "thanksgiving-us-2026")
    assert thanksgiving.for_countries?
    assert_equal %w[US], thanksgiving.country_codes
    assert_equal Time.utc(2026, 11, 26, 5), thanksgiving.starts_at
    assert_equal "Psalm 100:4", thanksgiving.scripture_reference

    assert_empty P.seed!(from: Date.new(2026, 11, 26))
  end

  test "auto-activate presets makes them live" do
    SiteSetting.switch(Celebration::AUTO_ACTIVATE_SETTING, true)
    created = P.seed!(from: Date.new(2026, 11, 26), months: 1)
    assert created.any?
    assert created.all?(&:live?)
  end
end

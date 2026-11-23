# frozen_string_literal: true

require "test_helper"

class CityTest < ActiveSupport::TestCase
  test "labels read City, Region, Country without repeats" do
    assert_equal "Akure, Ondo, Nigeria", cities(:akure).label
    assert_equal "Lagos, Nigeria", cities(:lagos).label
    assert_equal "Nairobi, Kenya", cities(:nairobi).label
    assert_equal "Toronto, Ontario, Canada", cities(:toronto).label
  end

  test "type-ahead matches the start of any name, own names and bigger places first" do
    assert_equal cities(:akure), City.search("aku").first
    assert_equal cities(:london), City.search("lon").first
    assert_includes City.search("ikorodu"), cities(:ebute_ikorodu)
    assert_includes City.search("harc"), cities(:port_harcourt)
    assert_includes City.search("Ile-If"), cities(:ile_ife)
    assert_empty City.search("a")
  end

  test "a region or country after a comma narrows, and the visitor's country is favoured" do
    assert_equal [ cities(:lagos) ], City.search("lagos, nigeria").to_a
    assert_equal [ cities(:london_ontario) ], City.search("London, Ontario").to_a
    assert_equal cities(:lagos), City.search("lagos").first
    assert_equal cities(:toronto), City.search("toronto", country: "NG").first
  end

  test "free text matches real cities, leaving unclear text alone" do
    assert_equal cities(:akure), City.match("Akure").city
    assert_equal cities(:akure), City.match("Akure, Nigeria").city
    assert_equal cities(:akure), City.match("Akure, Ondo State, Nigeria").city
    assert_equal cities(:houston), City.match("Houston, TX").city
    assert_equal cities(:los_angeles), City.match("Los Angeles, CA").city
    assert_equal cities(:new_york_city), City.match("New York, NY").city
    assert_equal :region_only, City.match("Ondo State, Nigeria").status
    assert_equal :vague, City.match("Online").status
    assert_equal :none, City.match("Atlantis").status
    assert_equal cities(:london), City.match("London").city
  end

  test "a country or a state on its own never becomes a city" do
    assert_equal :country_only, City.match("Nigeria").status
    assert_equal :country_only, City.match("Nigeria ").status
    assert_equal :country_only, City.match("USA 🇺🇸").status
    assert_equal :country_only, City.match("England").status
    assert_equal :region_only, City.match("Ekiti, Nigeria").status
    assert_equal :region_only, City.match("Ondo State, Nigeria").status
    assert_equal cities(:ondo), City.match("Ondo, Nigeria").city
    assert_equal cities(:lagos), City.match("Lagos, Nigeria").city
  end

  test "two places of a similar size are a guess, not a match" do
    City.create!(geonames_id: 1, name: "Springfield", country_code: "US", country_name: "United States", admin1_code: "IL", admin1_name: "Illinois", lat: 39.8, lng: -89.6, population: 114_000)
    City.create!(geonames_id: 2, name: "Springfield", country_code: "US", country_name: "United States", admin1_code: "MO", admin1_name: "Missouri", lat: 37.2, lng: -93.3, population: 169_000)

    assert_equal :ambiguous, City.match("Springfield").status
    assert_equal "Illinois", City.match("Springfield, IL").city.admin1_name
  end

  test "nearest city to a point, and distances between centres" do
    assert_equal cities(:akure), City.nearest(7.26, 5.21)
    assert_equal cities(:mississauga), City.nearest("43.58", "-79.65")
    assert_nil City.nearest("abc", "1")
    assert_nil City.nearest(95, 0)
    assert_in_delta 44, cities(:akure).distance_km_to(cities(:owo)), 2
  end
end

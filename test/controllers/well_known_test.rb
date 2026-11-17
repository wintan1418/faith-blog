# frozen_string_literal: true

require "test_helper"

# Android checks this file before letting brethreign.com links open in the app.
class WellKnownTest < ActionDispatch::IntegrationTest
  test "assetlinks.json names the Android app and its signing keys" do
    get "/.well-known/assetlinks.json"

    assert_response :success
    assert_equal "application/json", response.media_type
    target = response.parsed_body.first["target"]
    assert_equal "com.brethreign.app", target["package_name"]
    assert_equal 2, target["sha256_cert_fingerprints"].size
  end

  test "apple-app-site-association names the iPhone app once a Team ID is set" do
    get "/.well-known/apple-app-site-association"
    assert_response :not_found

    with_env("APPLE_TEAM_ID" => "ABCDE12345") do
      get "/.well-known/apple-app-site-association"
      assert_response :success
      assert_equal "application/json", response.media_type
      details = response.parsed_body.dig("applinks", "details").first
      assert_equal [ "ABCDE12345.com.brethreign.app" ], details["appIDs"]
      assert_includes details["components"], { "/" => "/posts*" }
    end
  end

  private

  def with_env(vars)
    saved = vars.keys.to_h { |k| [ k, ENV[k] ] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| ENV[k] = v }
  end
end

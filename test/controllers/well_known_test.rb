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
end

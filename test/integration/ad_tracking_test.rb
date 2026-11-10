# frozen_string_literal: true

require "test_helper"

class AdTrackingTest < ActionDispatch::IntegrationTest
  KEYS = %w[META_PIXEL_ID GOOGLE_TAG_ID GOOGLE_ADS_SIGNUP_CONVERSION].freeze

  setup { @saved = KEYS.to_h { |k| [ k, ENV[k] ] } }
  teardown { @saved.each { |k, v| ENV[k] = v } }

  def configure!
    ENV["META_PIXEL_ID"] = "123456789012345"
    ENV["GOOGLE_TAG_ID"] = "AW-1234567890"
    ENV["GOOGLE_ADS_SIGNUP_CONVERSION"] = "AW-1234567890/AbCdEf"
  end

  test "nothing is added until the IDs are set" do
    KEYS.each { |k| ENV.delete(k) }
    get root_path
    assert_select "[data-controller='ad-consent']", false
    assert_no_match "connect.facebook.net", response.body
  end

  test "Europe and the UK must say yes first; the US loads unless they say no" do
    configure!
    get root_path, headers: { "CF-IPCountry" => "GB" }
    assert_select "[data-controller='ad-consent'][data-ad-consent-required-value='true']"
    assert_select "[data-ad-consent-pixel-value='123456789012345']"

    get root_path, headers: { "CF-IPCountry" => "DE" }
    assert_select "[data-ad-consent-required-value='true']"

    get root_path, headers: { "CF-IPCountry" => "US" }
    assert_select "[data-ad-consent-required-value='false']"
  end

  test "never inside the apps" do
    configure!
    get root_path, headers: { "User-Agent" => "Brethreign/1.0.8; Hotwire Native Android; Turbo Native Android" }
    assert_select "[data-controller='ad-consent']", false
  end

  test "a new account is reported as a sign-up once" do
    configure!
    post user_registration_path, params: { user: { username: "ads_newbie", email: "ads-newbie@example.com", password: SecureRandom.base58(16) } }
    follow_redirect!
    assert_select "[data-ad-consent-signup-value='true']"

    get feed_path
    assert_select "[data-ad-consent-signup-value='false']"
  end

  test "malformed IDs are ignored" do
    ENV["META_PIXEL_ID"] = "<script>"
    ENV["GOOGLE_TAG_ID"] = "nope"
    get root_path
    assert_select "[data-controller='ad-consent']", false
  end
end

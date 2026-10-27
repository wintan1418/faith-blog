# frozen_string_literal: true

require "test_helper"

class AppUpdateNudgesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  APP = "Brethreign/%s; Hotwire Native Android; Turbo Native Android"

  setup do
    pass = SecureRandom.base58(16)
    @user = User.create!(username: "updater", email: "updater@example.com", password: pass, password_confirmation: pass)
    sign_in @user
    @previous = ENV["ANDROID_LATEST_VERSION"]
    ENV["ANDROID_LATEST_VERSION"] = "1.0.7"
  end

  teardown { ENV["ANDROID_LATEST_VERSION"] = @previous }

  def visit_as(version, path = feed_path)
    get path, headers: { "User-Agent" => format(APP, version) }
  end

  test "an older app version sees the update banner" do
    visit_as "1.0.6"
    assert_select ".fc-app-update", text: /1\.0\.7/
  end

  test "the latest version and the website see no banner" do
    visit_as "1.0.7"
    assert_select ".fc-app-update", false
    get feed_path
    assert_select ".fc-app-update", false
  end

  test "closing the banner hides it until the next release" do
    @user.dismiss_card!("app-update-1-0-7")
    visit_as "1.0.6"
    assert_select ".fc-app-update", false

    ENV["ANDROID_LATEST_VERSION"] = "1.0.8"
    visit_as "1.0.6"
    assert_select ".fc-app-update"
  end

  test "settings shows the app version and a check for updates button" do
    visit_as "1.0.7", edit_settings_account_path
    assert_select "a", text: "Check for updates"
    assert_match "You're up to date", response.body

    visit_as "1.0.6", edit_settings_account_path
    assert_select "a", text: "Update now"
  end
end

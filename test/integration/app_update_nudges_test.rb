# frozen_string_literal: true

require "test_helper"

class AppUpdateNudgesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

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

  test "Not now hides the banner for the week, and a new release brings it back" do
    @user.dismiss_card!("app-update-1-0-7-w#{Date.current.cweek}")
    visit_as "1.0.6"
    assert_select ".fc-app-update", false

    travel 8.days do
      visit_as "1.0.6"
      assert_select ".fc-app-update"
    end

    ENV["ANDROID_LATEST_VERSION"] = "1.0.8"
    visit_as "1.0.6"
    assert_select ".fc-app-update"
  end

  test "the latest version set on Admin → App versions wins over the env var" do
    AppRelease.create!(platform: "android", latest_version: "1.0.9")
    visit_as "1.0.8"
    assert_select ".fc-app-update", text: /1\.0\.9/
  end

  test "an app below the minimum version sees Update required instead of the page" do
    AppRelease.create!(platform: "android", latest_version: "1.0.8", minimum_version: "1.0.5")

    visit_as "1.0.4"
    assert_select "h1", "Please update Brethreign"
    assert_select "a[href*='play.google.com']"

    visit_as "1.0.4", privacy_path
    assert_select "h1", { text: "Please update Brethreign", count: 0 }

    visit_as "1.0.5"
    assert_select "h1", { text: "Please update Brethreign", count: 0 }
    get feed_path
    assert_select "h1", { text: "Please update Brethreign", count: 0 }
  end

  test "the app version a member uses is remembered" do
    visit_as "1.0.6"
    assert_equal "1.0.6", @user.reload.android_app_version

    @user.update_column(:last_seen_at, Time.current)
    visit_as "1.0.8"
    assert_equal "1.0.8", @user.reload.android_app_version
  end

  test "admins see who is behind and can remind them once every 3 days" do
    pass = SecureRandom.base58(16)
    admin = User.create!(username: "app_admin", email: "app-admin@example.com", password: pass, password_confirmation: pass, role: :admin)
    @user.update_column(:android_app_version, "1.0.6")
    sign_in admin

    patch admin_app_release_path, params: { app_release: { latest_version: "1.0.8", minimum_version: "1.0.9" } }
    assert_response :unprocessable_entity

    patch admin_app_release_path, params: { app_release: { latest_version: "1.0.8", minimum_version: "" } }
    assert_redirected_to edit_admin_app_release_path

    get edit_admin_app_release_path
    assert_select "td", text: /1\.0\.6 · behind/

    perform_enqueued_jobs { post remind_admin_app_release_path }
    assert_equal 1, @user.notifications.app_update.count
    assert_match "1.0.8 is out", @user.notifications.app_update.last.message

    perform_enqueued_jobs { post remind_admin_app_release_path }
    assert_equal 1, @user.notifications.app_update.count
  end

  test "members can't change app versions" do
    patch admin_app_release_path, params: { app_release: { latest_version: "9.9.9" } }
    assert_nil AppRelease.find_by(platform: "android")
  end

  test "settings shows the app version and a check for updates button" do
    visit_as "1.0.7", edit_settings_account_path
    assert_select "a", text: "Check for updates"
    assert_match "You're up to date", response.body

    visit_as "1.0.6", edit_settings_account_path
    assert_select "a", text: "Update now"
  end
end

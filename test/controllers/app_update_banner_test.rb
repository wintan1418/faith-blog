# frozen_string_literal: true

require "test_helper"

# Older Android app builds can't prompt for updates, so the site shows a bar.
class AppUpdateBannerTest < ActionDispatch::IntegrationTest
  def visit_about(user_agent)
    get about_path, headers: { "User-Agent" => user_agent }
  end

  test "the first app version (no version in its user agent) is asked to update" do
    visit_about "Hotwire Native Android; Turbo Native Android"
    assert_select ".fc-app-update a[href=?]", "https://play.google.com/store/apps/details?id=com.brethreign.app"
  end

  test "an up-to-date app sees no bar" do
    visit_about "Brethreign/1.0.1; NativeGoogleSignIn; Hotwire Native Android; Turbo Native Android"
    assert_select ".fc-app-update", count: 0
  end

  test "versions that update themselves never see the bar" do
    ENV["ANDROID_LATEST_VERSION"] = "1.0.5"
    visit_about "Brethreign/1.0.2; Hotwire Native Android; Turbo Native Android"
    assert_select ".fc-app-update", count: 0
  ensure
    ENV.delete("ANDROID_LATEST_VERSION")
  end

  test "the website and the iPhone app never see the bar" do
    visit_about "Mozilla/5.0 (Linux; Android 15) Chrome/130"
    assert_select ".fc-app-update", count: 0
    visit_about "Hotwire Native iOS; Turbo Native iOS"
    assert_select ".fc-app-update", count: 0
  end
end

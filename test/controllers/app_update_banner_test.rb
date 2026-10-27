# frozen_string_literal: true

require "test_helper"

# Inside the Android app, the site shows an update bar when Play has a newer version.
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

  test "the website and the iPhone app never see the bar" do
    visit_about "Mozilla/5.0 (Linux; Android 15) Chrome/130"
    assert_select ".fc-app-update", count: 0
    visit_about "Hotwire Native iOS; Turbo Native iOS"
    assert_select ".fc-app-update", count: 0
  end
end

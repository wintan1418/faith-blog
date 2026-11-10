# frozen_string_literal: true

require "test_helper"

class AdminDashboardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  BROWSER = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

  setup do
    @pass = SecureRandom.base58(16)
    @admin = User.create!(username: "dash_admin", email: "dash-admin@example.com", password: @pass, role: :admin)
    @member = User.create!(username: "dash_member", email: "dash-member@example.com", password: @pass)
  end

  test "page views are counted with where people came from, without cookies" do
    get root_path, headers: { "User-Agent" => BROWSER, "Referer" => "https://l.facebook.com/", "CF-IPCountry" => "NG" }
    visit = Ahoy::Visit.last
    assert_equal "NG", visit.country
    assert_equal "web", visit.platform
    assert_equal 1, Ahoy::Event.where(name: "$view").count
    assert_nil cookies["ahoy_visit"]
    assert_nil cookies["ahoy_visitor"]
  end

  test "admin pages and Turbo prefetches are not counted" do
    sign_in @admin
    get admin_root_path
    get root_path, headers: { "User-Agent" => BROWSER, "X-Sec-Purpose" => "prefetch" }
    assert_equal 0, Ahoy::Event.where(name: "$view").count
  end

  test "the Android app is recorded as the app" do
    get root_path, headers: { "User-Agent" => "Brethreign/1.0.8; Hotwire Native Android; Turbo Native Android" }
    visit = Ahoy::Visit.last
    assert_equal "android_app", visit.platform
    assert_equal "1.0.8", visit.app_version
  end

  test "the dashboard shows traffic, members, activity and safety for each period" do
    get root_path, headers: { "User-Agent" => BROWSER, "Referer" => "https://www.instagram.com/", "CF-IPCountry" => "GH" }
    reset!
    get root_path(utm_source: "whatsapp"), headers: { "User-Agent" => BROWSER.sub("18_0", "17_0") }
    @member.posts.create!(content: "Grateful today.", status: :published, published_at: Time.current)

    sign_in @admin
    [ 7, 30, 90 ].each do |days|
      get admin_root_path(days: days)
      assert_response :success
    end

    assert_select ".adash-kpi", 6
    assert_select ".adash-list__label", text: "Instagram"
    assert_select ".adash-list__label", text: "WhatsApp"
    assert_select ".adash-list__label", text: /Ghana/
    assert_select ".adash-safety__item", 5
    assert_select "svg[aria-label^='Visitors per day']"
  end

  test "members can't open the dashboard" do
    sign_in @member
    get admin_root_path
    assert_response :redirect
  end
end

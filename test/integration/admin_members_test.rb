# frozen_string_literal: true

require "test_helper"

class AdminMembersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    pass = SecureRandom.base58(16)
    @admin = User.create!(username: "members_admin", email: "members-admin@example.com", password: pass, role: :admin)
    @app_user = User.create!(username: "app_member", email: "app-member@example.com", password: pass,
                             android_app_version: "1.0.8", last_seen_at: 1.minute.ago)
    @old = User.create!(username: "old_member", email: "old-member@example.com", password: pass, active: false)
    @old.update_column(:created_at, 40.days.ago)
  end

  test "the dashboard shows the total members, growth and breakdown" do
    sign_in @admin
    get admin_root_path
    assert_response :success
    assert_select ".adash-members__value", text: User.count.to_s
    assert_select "h2", text: "Members over time"
    assert_select ".adash-members__tiles .adash-kpi__label", text: "On the Android app"
    assert_select "h2", text: "Where members are"
  end

  test "the growth series ends at today's total" do
    stats = AdminDashboardStats.new(30)
    growth = stats.members_growth
    assert_equal 26, growth.size
    assert_equal User.count, growth.last.last
  end

  test "the members list shows the total, searches and filters" do
    sign_in @admin
    get admin_users_path
    assert_response :success
    assert_match "#{User.count} ", response.body

    get admin_users_path(q: "app-member")
    assert_select "td", text: /app_member/
    assert_select "td", text: /old_member/, count: 0

    get admin_users_path(filter: "android")
    assert_select "td", text: /app_member/
    assert_select "td", text: /old_member/, count: 0

    get admin_users_path(filter: "suspended")
    assert_select "td", text: /old_member/
  end

  test "members cannot see the list" do
    sign_in @app_user
    get admin_users_path
    assert_response :redirect
  end
end

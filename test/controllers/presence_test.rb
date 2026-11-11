# frozen_string_literal: true

require "test_helper"

# Who's online: heartbeat, the feed's "Online now" row, the privacy switch and Admin → Online now.
class PresenceTest < ActionDispatch::IntegrationTest
  setup do
    @me = create_member("presence_me")
    @friend = create_member("presence_friend")
  end

  # ── Heartbeat ──

  test "ping marks the member as seen and returns no content" do
    @me.update_column(:last_seen_at, 10.minutes.ago)
    sign_in @me

    post presence_ping_path
    assert_response :no_content
    assert_in_delta Time.current, @me.reload.last_seen_at, 5.seconds
    assert @me.online?
  end

  test "ping needs a signed-in member" do
    post presence_ping_path
    assert_response :unauthorized
  end

  test "ping does not write again within the throttle" do
    seen = 5.seconds.ago.change(usec: 0)
    @me.update_column(:last_seen_at, seen)
    sign_in @me

    post presence_ping_path
    assert_response :no_content
    assert_equal seen, @me.reload.last_seen_at
  end

  # ── Model ──

  test "online scope and online? use the shared window" do
    @me.update_column(:last_seen_at, (User::ONLINE_WINDOW - 10.seconds).ago)
    @friend.update_column(:last_seen_at, (User::ONLINE_WINDOW + 10.seconds).ago)

    assert_equal 2.minutes, User::ONLINE_WINDOW
    assert_includes User.online, @me
    assert_not_includes User.online, @friend
    assert @me.online?
    assert_not @friend.online?
  end

  test "hidden members are never visibly online and show no last-seen label" do
    @friend.update_columns(last_seen_at: Time.current, show_online_status: false)

    assert @friend.online?
    assert_not @friend.visible_online?
    assert_nil @friend.presence_label
    @friend.update_column(:show_online_status, true)
    assert_equal "Active now", @friend.presence_label
  end

  # ── Feed strip ──

  test "feed shows who else is online, without me" do
    @me.update_column(:last_seen_at, Time.current)
    @friend.update_column(:last_seen_at, Time.current)
    sign_in @me

    get feed_path
    assert_response :success
    assert_select "turbo-frame#online_now .fc-online" do
      assert_select ".fc-online-head strong", "1"
      assert_select "a.fc-online-person[href=?]", user_path(@friend.username)
      assert_select "a.fc-online-person[href=?]", user_path(@me.username), false
    end
  end

  test "feed strip leaves out hidden, offline, suspended and blocked members" do
    hidden = create_member("presence_hidden", show_online_status: false)
    offline = create_member("presence_offline")
    suspended = create_member("presence_suspended", active: false)
    blocked = create_member("presence_blocked")
    blocker = create_member("presence_blocker")
    [ hidden, suspended, blocked, blocker ].each { |u| u.update_column(:last_seen_at, Time.current) }
    offline.update_column(:last_seen_at, 10.minutes.ago)
    MessageBlock.create!(blocker: @me, blocked: blocked)
    MessageBlock.create!(blocker: blocker, blocked: @me)
    @friend.update_column(:last_seen_at, Time.current)

    online = OnlinePresence.new(@me)
    assert_equal [ @friend ], online.users
    assert_equal 1, online.count

    sign_in @me
    get presence_strip_path
    assert_response :success
    assert_select "turbo-frame#online_now a.fc-online-person", 1
    [ hidden, offline, suspended, blocked, blocker ].each do |u|
      assert_select "a.fc-online-person[href=?]", user_path(u.username), false
    end
  end

  test "people I follow come first in the strip" do
    others = Array.new(3) { |i| create_member("presence_other#{i}") }
    others.each { |u| u.update_column(:last_seen_at, Time.current) }
    @friend.update_column(:last_seen_at, 1.minute.ago)
    @me.follow(@friend)

    assert_equal @friend, OnlinePresence.new(@me).users.first
  end

  test "feed strip renders an empty frame when nobody else is online" do
    sign_in @me
    get presence_strip_path
    assert_response :success
    assert_select "turbo-frame#online_now"
    assert_select ".fc-online", false
  end

  test "strip needs a signed-in member" do
    get presence_strip_path
    assert_redirected_to new_user_session_path
  end

  # ── Privacy setting ──

  test "privacy settings save show when I'm online" do
    sign_in @me
    get edit_settings_privacy_path
    assert_select "input[type=checkbox][name='user[show_online_status]'][checked]"

    patch settings_privacy_path, params: { profile: { public_profile: "1" }, user: { show_online_status: "0" } }
    assert_redirected_to edit_settings_privacy_path
    assert_not @me.reload.show_online_status?

    patch settings_privacy_path, params: { profile: { public_profile: "1" }, user: { show_online_status: "1" } }
    assert @me.reload.show_online_status?
  end

  # ── Admin ──

  test "admin dashboard shows the live online count, including hidden members" do
    admin = create_member("presence_admin", role: :admin)
    @friend.update_columns(last_seen_at: Time.current, show_online_status: false)
    sign_in admin

    get admin_root_path
    assert_response :success
    assert_select "turbo-frame#admin_online_now .adash-online__value", /2/ # admin + hidden friend

    get admin_online_path
    assert_response :success
    assert_select "turbo-frame#admin_online_now .adash-people a[href=?]", admin_user_path(@friend)
  end

  test "non-admins can't see Admin → Online now" do
    sign_in @me
    get admin_online_path
    assert_redirected_to root_path
  end
end

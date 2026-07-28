# frozen_string_literal: true

require "test_helper"

# Prayer Circles: private groups with a members-only stream and a shared
# prayer list, joined by invite link only.
class PrayerCirclesTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(username: "circle_owner", email: "cowner@example.com",
                          password: "password123", password_confirmation: "password123")
    @friend = User.create!(username: "circle_friend", email: "cfriend@example.com",
                           password: "password123", password_confirmation: "password123")
    @stranger = User.create!(username: "circle_stranger", email: "cstranger@example.com",
                             password: "password123", password_confirmation: "password123")
  end

  def create_circle
    sign_in @owner
    post circles_path, params: { circle: { name: "Tuesday Cell", description: "Us" } }
    Circle.find_by!(name: "Tuesday Cell")
  end

  test "creating a circle makes the creator its owner-member" do
    circle = create_circle
    assert circle.member?(@owner)
    assert circle.owned_by?(@owner)
    assert_equal 1, circle.members_count
    assert circle.invite_code.present?
    assert circle.slug.present?
  end

  test "non-members are turned away from a private circle" do
    circle = create_circle
    sign_in @stranger
    get circle_path(circle)
    assert_redirected_to circles_path
    follow_redirect!
    assert_match(/private/i, response.body)
  end

  test "joining by invite link admits, garbage codes bounce" do
    circle = create_circle
    sign_in @friend

    get join_circle_path(code: circle.invite_code)
    assert_redirected_to circle_path(circle)
    assert circle.reload.member?(@friend)
    assert_equal 2, circle.members_count

    get join_circle_path(code: "not-a-real-code")
    assert_redirected_to circles_path
  end

  test "a breath in the circle notifies the other members only" do
    circle = create_circle
    circle.circle_memberships.create!(user: @friend)

    sign_in @owner
    assert_difference -> { @friend.notifications.circle_breath.count }, 1 do
      assert_no_difference -> { @owner.notifications.count } do
        post circle_breaths_path(circle), params: { circle_breath: { body: "Grace tonight, brethren." } }
      end
    end

    get circle_path(circle)
    assert_match "Grace tonight, brethren.", response.body
  end

  test "prayer list: add, amen toggle, mark answered with notification" do
    circle = create_circle
    circle.circle_memberships.create!(user: @friend)

    sign_in @owner
    assert_difference -> { @friend.notifications.circle_prayer.count }, 1 do
      post circle_prayers_path(circle), params: { circle_prayer: { title: "Job interview Friday" } }
    end
    prayer = circle.prayers.find_by!(title: "Job interview Friday")

    sign_in @friend
    post amen_circle_prayer_path(circle, prayer)
    assert_equal 1, prayer.reload.amens_count
    post amen_circle_prayer_path(circle, prayer)
    assert_equal 0, prayer.reload.amens_count, "amen must toggle off"

    # Only the asker or owner can mark answered.
    post answered_circle_prayer_path(circle, prayer)
    assert prayer.reload.prayer_open?

    sign_in @owner
    assert_difference -> { @friend.notifications.circle_prayer_answered.count }, 1 do
      post answered_circle_prayer_path(circle, prayer)
    end
    assert prayer.reload.prayer_answered?
    assert prayer.answered_at.present?
  end

  test "members can leave but owners must dissolve" do
    circle = create_circle
    circle.circle_memberships.create!(user: @friend)

    sign_in @friend
    delete leave_circle_path(circle)
    assert_not circle.reload.member?(@friend)

    sign_in @owner
    delete leave_circle_path(circle)
    assert circle.reload.member?(@owner), "owner cannot leave their own circle"

    delete circle_path(circle)
    assert_nil Circle.find_by(id: circle.id)
  end

  test "rotating the invite kills the old link" do
    circle = create_circle
    old_code = circle.invite_code

    post rotate_invite_circle_path(circle)
    assert_not_equal old_code, circle.reload.invite_code

    sign_in @friend
    get join_circle_path(code: old_code)
    assert_redirected_to circles_path
    assert_not circle.reload.member?(@friend)
  end
end

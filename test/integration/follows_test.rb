# frozen_string_literal: true

require "test_helper"

class FollowsTest < ActionDispatch::IntegrationTest
  setup do
    @follower = create_user("follower")
    @followed = create_user("followed")

    sign_in @follower
  end

  test "follow updates button target over turbo stream" do
    post follow_user_path(@followed.username), as: :turbo_stream

    assert_response :success
    assert @follower.following?(@followed)
    assert_includes response.body, dom_id(@followed, :follow_actions)
    assert_includes response.body, "Following"
  end

  test "unfollow updates button target over turbo stream" do
    @follower.follow(@followed)

    delete unfollow_user_path(@followed.username), as: :turbo_stream

    assert_response :success
    assert_not @follower.following?(@followed)
    assert_includes response.body, dom_id(@followed, :follow_actions)
    assert_includes response.body, "Follow"
  end

  private

  def create_user(username)
    User.create!(
      username: username,
      email: "#{username}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end
end

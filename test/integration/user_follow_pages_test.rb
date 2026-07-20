# frozen_string_literal: true

require "test_helper"

# /u/:username/followers and /u/:username/following must render real pages.
# They used to 406 with an empty body (no templates existed) — the infamous
# blank white page.
class UserFollowPagesTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(username: "page_owner", email: "page_owner@example.com",
                          password: "password123", password_confirmation: "password123")
    @fan = User.create!(username: "page_fan", email: "page_fan@example.com",
                        password: "password123", password_confirmation: "password123")
    @idol = User.create!(username: "page_idol", email: "page_idol@example.com",
                         password: "password123", password_confirmation: "password123")
    @fan.follow(@owner)
    @owner.follow(@idol)
    sign_in @fan
  end

  test "followers page renders the people who follow the user" do
    get followers_user_path(@owner.username)

    assert_response :success
    assert_match "Followers", response.body
    assert_match "@page_fan", response.body
    assert_no_match "@page_idol", response.body
  end

  test "following page renders the people the user follows" do
    get following_user_path(@owner.username)

    assert_response :success
    assert_match "Following", response.body
    assert_match "@page_idol", response.body
    assert_no_match "@page_fan", response.body
  end

  test "empty states render instead of a blank page" do
    get followers_user_path(@fan.username)
    assert_response :success
    assert_match "No followers yet", response.body
  end

  test "private profiles do not expose their follow lists" do
    @owner.profile.update!(public_profile: false)

    get followers_user_path(@owner.username)
    assert_redirected_to user_path(@owner.username)

    get following_user_path(@owner.username)
    assert_redirected_to user_path(@owner.username)
  end
end

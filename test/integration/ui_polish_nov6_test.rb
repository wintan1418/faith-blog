# frozen_string_literal: true

require "test_helper"

# Fixes from the 6 November UI review.
class UiPolishNov6Test < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @pass = SecureRandom.base58(16)
    @ada = User.create!(username: "ada_ui6", email: "ada-ui6@example.com", password: @pass, password_confirmation: @pass)
    @ben = User.create!(username: "ben_ui6", email: "ben-ui6@example.com", password: @pass, password_confirmation: @pass)
    @room = Room.create!(name: "UI6 Room", description: "x", is_public: true)
    @post = Post.create!(title: "Grace for today", content: "Grace, @ben_ui6.", room: @room, user: @ada, status: "published")
  end

  test "people in the who-reacted list open as a whole page, not inside the list" do
    @post.likes.create!(user: @ben, reaction_type: :love, reaction_emoji: "❤️")
    sign_in @ada
    get reactions_post_path(@post)
    assert_select "#reactors_panel a.fc-reactor-link[href=?][data-turbo-frame=_top]", user_path(@ben.username)
  end

  test "@mentions open profiles as a whole page, also inside reply threads" do
    sign_in @ada
    get post_path(@post)
    assert_select "a.mention-link[href=?][data-turbo-frame=_top]", user_path(@ben.username)
  end

  test "following again within a week doesn't repeat the alert" do
    follow = Follow.create!(follower: @ben, following: @ada)
    follow.destroy
    Follow.create!(follower: @ben, following: @ada)
    assert_equal 1, Notification.where(user: @ada, actor: @ben, notification_type: :new_follower).count
  end

  test "the alerts page is called Alerts" do
    sign_in @ada
    get notifications_path
    assert_select "h1.fc-notifpage-title", text: "Alerts"
  end
end

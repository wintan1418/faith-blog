# frozen_string_literal: true

require "test_helper"

# The apps show the page <title> in their native top bar, without the site suffix.
class NativeAppTitleTest < ActionDispatch::IntegrationTest
  APP_USER_AGENT = "Brethreign/1.0 Hotwire Native Android; Turbo Native Android"

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @author = User.create!(username: "title_author", email: "title_author@example.com",
                           password: "password123", password_confirmation: "password123")
    room = Room.create!(name: "Title Room", description: "x", room_type: :general, is_public: true)
    @post = Post.create!(user: @author, room: room, title: "The Shepherd's Psalm",
                         content: "Grace and peace.", status: :published, moderation_status: :approved)
  end

  test "apostrophes in app titles are not double-escaped" do
    sign_in @author
    get post_path(@post), headers: { "User-Agent" => APP_USER_AGENT }

    assert_response :success
    assert_select "title", text: "The Shepherd's Psalm"
    assert_no_match "&amp;#39;", response.body[/<title>.*?<\/title>/m]
  end

  test "the website keeps the full title" do
    sign_in @author
    get post_path(@post)

    assert_select "title", text: "The Shepherd's Psalm - Brethreign"
  end
end

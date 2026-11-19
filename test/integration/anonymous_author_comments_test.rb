# frozen_string_literal: true

require "test_helper"

# The author of an anonymous post must stay anonymous when they comment on it.
class AnonymousAuthorCommentsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    seen = { tour_completed_at: Time.current, welcomed_at: Time.current }
    @author = create_member("secret_author", **seen)
    @reader = create_member("curious_reader", **seen)
    room = Room.create!(name: "Prayer Wall", description: "x", room_type: :general, is_public: true)
    @post = Post.create!(user: @author, room: room, title: "Please pray", content: "A hard season",
                         status: :published, moderation_status: :approved, anonymous: true)
    Comment.create!(post: @post, user: @author, content: "Thank you all for praying", moderation_status: :approved)
  end

  test "readers see Anonymous, not the author's name" do
    sign_in @reader
    get post_path(@post)
    assert_response :success
    assert_select ".cm-name", text: "Anonymous"
    assert_no_match "secret_author", response.body
  end

  test "the author still sees their own name" do
    sign_in @author
    get post_path(@post)
    assert_select ".cm-name", text: "secret_author"
  end
end

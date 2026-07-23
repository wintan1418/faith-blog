# frozen_string_literal: true

require "test_helper"

# Trix formatting must SURVIVE on the post page — the old renderer
# flattened everything to plain text, silently erasing bold, italics,
# headings, and lists — while mentions and URLs still become links.
class RichTextRenderingTest < ActionDispatch::IntegrationTest
  setup do
    @author = User.create!(username: "rich_author", email: "rich_author@example.com",
                           password: "password123", password_confirmation: "password123")
    @mentioned = User.create!(username: "rich_friend", email: "rich_friend@example.com",
                              password: "password123", password_confirmation: "password123")
    @room = Room.create!(name: "Rich Room", description: "x")
    sign_in @author
  end

  test "bold, italics, and headings render on the post page, with mentions linked" do
    post_record = Post.create!(
      user: @author, room: @room, title: "Formatted breath",
      content: "<h1>A subheading</h1><div><strong>Bold truth</strong> and <em>gentle italics</em> " \
               "with @rich_friend and https://example.com/grace</div>",
      status: :published, moderation_status: :approved
    )

    get post_path(post_record)
    assert_response :success

    assert_select ".post-body strong", text: "Bold truth"
    assert_select ".post-body em", text: "gentle italics"
    assert_select ".post-body h1", text: "A subheading"
    assert_select ".post-body a[href=?]", user_path(@mentioned.username), text: "@rich_friend"
    assert_select ".post-body a[href='https://example.com/grace']"
  end

  test "script tags never survive rendering" do
    post_record = Post.create!(
      user: @author, room: @room, title: "Sneaky breath",
      content: "<div>hello<script>alert(1)</script></div>",
      status: :published, moderation_status: :approved
    )

    get post_path(post_record)
    assert_response :success
    assert_no_match "<script>alert(1)</script>", response.body
  end
end

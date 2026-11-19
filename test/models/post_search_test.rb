# frozen_string_literal: true

require "test_helper"

# Post.search reads the stored `searchable` tsvector (title + plain-text body).
class PostSearchTest < ActiveSupport::TestCase
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @author = User.create!(username: "searcher", email: "searcher@example.com", password: "password123")
    @room = Room.create!(name: "Search Room", description: "x", room_type: :general, is_public: true)
  end

  def make_post(title, body)
    Post.create!(user: @author, room: @room, title: title, content: body, status: :published, moderation_status: :approved)
  end

  test "finds posts by words in the body, the title, and by prefix" do
    post = make_post("Morning thoughts", "<div>The <strong>shepherd</strong> leaves the ninety-nine.</div>")
    other = make_post("Evening thoughts", "Rest and quiet.")

    assert_equal [ post ], Post.search("shepherd").to_a
    assert_equal [ post ], Post.search("shepherds").to_a # english stemming
    assert_equal [ post ], Post.search("shep").to_a      # prefix
    assert_equal [ other ], Post.search("evening").to_a
    assert_empty Post.search("strong").to_a, "HTML tags aren't indexed"
  end

  test "editing the body or title refreshes the index" do
    post = make_post("Morning thoughts", "Grace upon grace.")
    assert_empty Post.search("covenant").to_a

    post.reload.update!(content: "An everlasting covenant.")
    assert_equal [ post ], Post.search("covenant").to_a
    assert_empty Post.search("grace").to_a

    post.reload.update!(title: "Psalm of ascent")
    assert_equal [ post ], Post.search("ascent").to_a
  end

  test "search works with the card includes and the published scope" do
    post = make_post("Hidden gem", "Treasure in a field.")
    assert_equal [ post ], Post.published.search("treasure").for_cards.to_a
  end

  test "the stored vector isn't selected with posts" do
    refute_includes Post.first(1).first&.attributes.to_h.keys, "searchable"
  end
end

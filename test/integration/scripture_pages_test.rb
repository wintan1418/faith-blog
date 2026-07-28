# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Scripture pages: /scripture/john-3-16 shows the verse and the breaths
# that mention it, without requiring sign-in.
class ScripturePagesTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @author = User.create!(username: "verse_author", email: "verse@example.com",
                           password: "password123", password_confirmation: "password123")
    @room = Room.create!(name: "Verse Room", description: "x")
  end

  teardown { ENV.delete("AI_MODERATION_STUB") }

  PAYLOAD = { reference: "John 3:16", text: "For God so loved the world...",
              verses: [], translation: "KJV" }.freeze

  test "shows the verse text and matching breaths, publicly" do
    Post.create!(user: @author, room: @room, title: "So loved",
                 content: "Standing on John 3:16 tonight.", status: :published,
                 moderation_status: :approved)
    Post.create!(user: @author, room: @room, title: "Other verse",
                 content: "Psalm 23 comfort.", status: :published,
                 moderation_status: :approved)

    ScriptureLookup.stub(:lookup, PAYLOAD) do
      get scripture_page_path(slug: "john-3-16")
    end

    assert_response :success
    assert_match "John 3:16", response.body
    assert_match "For God so loved", response.body
    assert_match "So loved", response.body
    assert_no_match(/Other verse/, response.body)
  end

  test "numbered books and chapter-only slugs parse" do
    ScriptureLookup.stub(:lookup, nil) do
      get scripture_page_path(slug: "1-john-4-19")
      assert_response :success
      assert_match "1 John 4:19", response.body

      get scripture_page_path(slug: "psalm-23")
      assert_response :success
      assert_match "Psalm 23", response.body
    end
  end

  test "garbage slugs 404" do
    get "/scripture/not-a-verse"
    assert_response :not_found
  rescue ActiveRecord::RecordNotFound
    assert true
  end
end

# frozen_string_literal: true

require "test_helper"

# Google still had old breath addresses (the slug plus an id on the end) as 404s
# and duplicates; they now move for good to the current address.
class LegacyPostRedirectTest < ActionDispatch::IntegrationTest
  setup do
    pass = SecureRandom.base58(16)
    @author = User.create!(username: "legacy_author", email: "legacy-author@example.com", password: pass, password_confirmation: pass)
    @room = Room.create!(name: "Legacy Room", description: "x", is_public: true)
    @post = Post.create!(user: @author, room: @room, title: "Tech and my faith surviving in Babylon", content: "Body",
                         status: :published, moderation_status: :approved, published_at: Time.current)
  end

  test "an old slug with an id on the end redirects permanently to the current address" do
    get "/posts/#{@post.slug}-3257b984-9421-4b34-bfe6-eb1bec504d74"
    assert_response :moved_permanently
    assert_redirected_to post_path(@post)
  end

  test "an unknown address still 404s for visitors" do
    get "/posts/nothing-here-3257b984-9421-4b34-bfe6-eb1bec504d74"
    assert_response :not_found
  end

  test "the current address still works" do
    get post_path(@post)
    assert_response :success
  end
end

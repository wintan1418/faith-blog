require "test_helper"

class ResharesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @author = User.create!(
      username: "reshare_user",
      email: "reshare@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @reader = User.create!(
      username: "reshare_reader",
      email: "reshare-reader@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    @room = Room.create!(name: "Test Room", description: "A room for tests", room_type: :general, is_public: true)
    @post = Post.create!(
      user: @author,
      room: @room,
      title: "A valid test post",
      content: "This is a valid post body.",
      status: :published
    )
  end

  test "authenticated user can reshare and remove a post" do
    sign_in @reader

    assert_difference("Reshare.count", 1) do
      post post_reshare_path(@post)
    end

    assert_difference("Reshare.count", -1) do
      delete post_reshare_path(@post)
    end
  end
end

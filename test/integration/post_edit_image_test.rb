# frozen_string_literal: true

require "test_helper"

# Editing a post and attaching a file that fails validation must re-render
# the form with errors — not 500 trying to thumbnail the unsaved upload
# ("Cannot get a signed_id for a new record").
class PostEditImageTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @author = User.create!(username: "img_author", email: "img_author@example.com",
                           password: "password123", password_confirmation: "password123")
    @room = Room.create!(name: "Img Room", description: "x")
    @post = Post.create!(user: @author, room: @room, title: "Picture breath",
                         content: "Body", status: :published, moderation_status: :approved)
    sign_in @author
  end

  teardown { ENV.delete("AI_MODERATION_STUB") }

  test "a failed image upload re-renders the edit form instead of crashing" do
    bad_file = Tempfile.new([ "not_an_image", ".txt" ])
    bad_file.write("just text")
    bad_file.rewind

    patch post_path(@post), params: { post: {
      title: @post.title, content: "Body",
      images: [ Rack::Test::UploadedFile.new(bad_file.path, "text/plain") ]
    } }

    assert_response :unprocessable_entity, "expected a validation re-render, not a 500"
    assert_match(/must be JPG|image|type/i, response.body)
  ensure
    bad_file.close!
  end
end

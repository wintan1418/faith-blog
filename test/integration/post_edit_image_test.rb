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

  TINY_PNG = Base64.decode64(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
  )

  def png_upload(name)
    file = Tempfile.new([ name, ".png" ])
    file.binmode
    file.write(TINY_PNG)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "image/png")
  end

  test "uploading a new image on edit appends instead of replacing" do
    @post.images.attach(io: StringIO.new(TINY_PNG), filename: "first.png", content_type: "image/png")
    assert_equal 1, @post.images.count

    patch post_path(@post), params: { post: {
      title: @post.title, content: "Body",
      images: [ png_upload("second") ]
    } }

    assert_response :redirect
    assert_equal 2, @post.reload.images.count, "new upload must append, not replace"
  end

  test "remove_image_ids purges only the ticked images" do
    @post.images.attach(io: StringIO.new(TINY_PNG), filename: "keep.png", content_type: "image/png")
    @post.images.attach(io: StringIO.new(TINY_PNG), filename: "drop.png", content_type: "image/png")
    drop_id = @post.images.attachments.find { |a| a.filename.to_s == "drop.png" }.id

    patch post_path(@post), params: { post: {
      title: @post.title, content: "Body",
      remove_image_ids: [ drop_id.to_s ]
    } }

    assert_response :redirect
    filenames = @post.reload.images.attachments.map { |a| a.filename.to_s }
    assert_equal [ "keep.png" ], filenames
  end

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

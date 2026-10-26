# frozen_string_literal: true

require "test_helper"

# Pictures get the same AI look as text. (The offline test moderator flags by file name.)
class ImageModerationTest < ActiveSupport::TestCase
  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")

  def image(name) = { io: StringIO.new(PNG), filename: name, content_type: "image/png" }

  def make_user(name)
    User.create!(username: name, email: "#{name}@example.com", password: "Pw-#{SecureRandom.hex(8)}")
  end

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @sender = make_user("pic_sender")
    @recipient = make_user("pic_recipient")
  end

  test "an explicit photo in a post makes the gate block it" do
    room = Room.create!(name: "Pic Room", description: "x", room_type: :general, is_public: true)
    post = Post.new(user: @sender, room: room, title: "Sunset", content: "God's creation", status: :published)
    post.images.attach(image("nsfw.png"))
    post.save! # the gate runs after saving, once the photo is uploaded

    verdict = Ai::Moderation::PostGatekeeper.call(post: post)
    assert verdict.block?
    assert_includes verdict.categories, "explicit_adult"
  end

  test "an ordinary photo in a post is fine" do
    room = Room.create!(name: "Pic Room 2", description: "x", room_type: :general, is_public: true)
    post = Post.new(user: @sender, room: room, title: "Sunset", content: "God's creation", status: :published)
    post.images.attach(image("sunset.png"))
    post.save!

    assert Ai::Moderation::PostGatekeeper.call(post: post).allow?
  end

  test "a photo-only message with an explicit picture is removed and not notified" do
    conversation = Conversation.find_or_create_between!(@sender, @recipient)
    message = conversation.messages.new(sender: @sender)
    message.images.attach(image("nsfw.png"))
    message.save!

    assert message.reload.removed?
    assert_equal 0, @recipient.notifications.direct_message.count
  end

  test "an explicit profile photo is taken down and the person is told" do
    @sender.profile.avatar.attach(image("nsfw.png"))
    @sender.profile.save!

    assert_not @sender.profile.reload.avatar.attached?
    assert_equal 1, @sender.notifications.content_removed.count
  end

  test "an ordinary profile photo stays" do
    @sender.profile.avatar.attach(image("me.png"))
    @sender.profile.save!

    assert @sender.profile.reload.avatar.attached?
  end
end

# frozen_string_literal: true

require "test_helper"

# Authorization regressions fixed in the app-hardening pass: you should not be
# able to react to / bookmark / reshare content you are not allowed to see.
class FeedHardeningTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @author = User.create!(username: "harden_author", email: "harden_author@example.com",
                           password: "password123", password_confirmation: "password123")
    @reader = User.create!(username: "harden_reader", email: "harden_reader@example.com",
                           password: "password123", password_confirmation: "password123")
    @outsider = User.create!(username: "harden_outsider", email: "harden_outsider@example.com",
                             password: "password123", password_confirmation: "password123")
    @room = Room.create!(name: "Harden Room", description: "x", room_type: :general, is_public: true)
    @held = Post.create!(user: @author, room: @room, title: "Held breath",
                         content: "Awaiting review.", status: :published,
                         moderation_status: :pending_review)
  end

  test "a held post cannot be liked by another user" do
    sign_in @reader
    assert_no_difference("Like.count") do
      post likes_path(likeable_type: "Post", likeable_id: @held.id, reaction_emoji: "🙏")
    end
  end

  test "a held post cannot be bookmarked by another user" do
    sign_in @reader
    assert_no_difference("Bookmark.count") do
      post post_bookmark_path(@held)
    end
  end

  test "a held post cannot be reshared by another user" do
    sign_in @reader
    assert_no_difference("Reshare.count") do
      post post_reshare_path(@held)
    end
  end

  test "the author can still bookmark their own held post" do
    sign_in @author
    assert_difference("Bookmark.count", 1) do
      post post_bookmark_path(@held)
    end
  end

  test "a non-participant cannot react to a private message" do
    convo = Conversation.find_or_create_between!(@author, @reader)
    message = Message.create!(conversation: convo, sender: @author, body: "private words")

    sign_in @outsider
    assert_no_difference("Like.count") do
      post likes_path(likeable_type: "Message", likeable_id: message.id, reaction_emoji: "🙏")
    end
  end

  test "a participant can react to a message in their conversation" do
    convo = Conversation.find_or_create_between!(@author, @reader)
    message = Message.create!(conversation: convo, sender: @author, body: "hello friend")

    sign_in @reader
    assert_difference("Like.count", 1) do
      post likes_path(likeable_type: "Message", likeable_id: message.id, reaction_emoji: "🙏")
    end
  end
end

# frozen_string_literal: true

require "test_helper"

# Offensive words are refused before saving; the AI removes sexual, occult and
# fraud messages and holds back the recipient's notification.
class ModerationTest < ActiveSupport::TestCase
  def make_user(name)
    User.create!(username: name, email: "#{name}@example.com", password: test_password)
  end

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @sender = make_user("sender")
    @recipient = make_user("recipient")
    @conversation = Conversation.find_or_create_between!(@sender, @recipient)
  end

  test "messages with offensive words aren't saved" do
    message = @conversation.messages.new(sender: @sender, body: "you are a f*cking fool")

    assert_not message.save
    assert_includes message.errors[:base], CleanLanguage::MESSAGE
  end

  test "comments and posts with offensive words aren't saved" do
    room = Room.create!(name: "Mod Room", description: "x", room_type: :general, is_public: true)
    post = Post.new(user: @sender, room: room, title: "Hello", content: "this is bullshit", status: :published)
    assert_not post.valid?

    good = Post.create!(user: @sender, room: room, title: "Hello", content: "Grace to you", status: :published)
    assert_not good.comments.new(user: @recipient, content: "b!tch please").valid?
  end

  test "offensive usernames are refused" do
    user = User.new(username: "big_bitch", email: "bb@example.com", password: test_password)

    assert_not user.valid?
    assert user.errors[:username].any?
  end

  test "a scam message is removed for both people and the recipient isn't notified" do
    message = @conversation.messages.create!(sender: @sender, body: "Hello, please send me your bank details and OTP")

    assert message.reload.removed?
    assert_equal 0, @recipient.notifications.direct_message.count
    review = AiModerationReview.find_by!(reviewable: message)
    assert review.flagged?
    assert_includes review.categories, "scam"
  end

  test "occult offers are removed too" do
    message = @conversation.messages.create!(sender: @sender, body: "I know a native doctor for money ritual")

    assert message.reload.removed?
  end

  test "a normal message goes through and notifies the recipient" do
    message = @conversation.messages.create!(sender: @sender, body: "Praying for you today, sister")

    assert_not message.reload.removed?
    assert_equal 1, @recipient.notifications.direct_message.count
  end

  test "a moderator can restore a message the AI removed" do
    message = @conversation.messages.create!(sender: @sender, body: "send me money for forex")
    assert message.reload.removed?

    message.restore_after_review!
    assert_not message.reload.removed?
    assert_equal 1, @recipient.notifications.direct_message.count
  end
end

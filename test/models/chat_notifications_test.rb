# frozen_string_literal: true

require "test_helper"

# QA: chat messages shouldn't flood Alerts, one notification per conversation,
# and reading the conversation clears it.
class ChatNotificationsTest < ActiveSupport::TestCase
  def make_user(name)
    User.create!(username: name, email: "#{name.downcase}@example.com", password: "password123", password_confirmation: "password123")
  end

  setup do
    @maria = make_user("MariaHope")
    @me = make_user("Faithful")
    @conversation = Conversation.find_or_create_between!(@maria, @me)
  end

  test "a burst of messages makes one notification that counts them" do
    assert_difference -> { @me.notifications.direct_message.count }, 1 do
      @conversation.messages.create!(sender: @maria, body: "Hi John")
      @conversation.messages.create!(sender: @maria, body: "Are you free tonight?")
      @conversation.messages.create!(sender: @maria, body: "Prayer meeting at 7")
    end

    notification = @me.notifications.direct_message.sole
    assert_equal "MariaHope sent you 3 messages", notification.message
    assert_equal "Prayer meeting at 7", notification.notifiable.body
  end

  test "a single message shows who and what" do
    @conversation.messages.create!(sender: @maria, body: "See you at 7")

    assert_equal "MariaHope: See you at 7", @me.notifications.direct_message.sole.message
  end

  test "messages stay out of the Alerts list and badge" do
    @conversation.messages.create!(sender: @maria, body: "Hello")

    assert_equal 0, @me.unread_notifications_count
    assert_empty @me.notifications.activity
    assert_equal 1, @me.unread_conversations_count
  end
end

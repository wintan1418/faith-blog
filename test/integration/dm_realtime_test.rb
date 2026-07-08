# frozen_string_literal: true

require "test_helper"

# Regression: a new message must reach the recipient's open thread in real time.
# The bug was that the message partial touched current_user, which raised when
# rendered in an Action Cable broadcast (no request), so the broadcast never
# reached the recipient — they only saw messages after re-rendering the thread.
class DmRealtimeTest < ActionDispatch::IntegrationTest
  include Turbo::Broadcastable::TestHelper

  setup do
    @sender = User.create!(username: "rt_sender", email: "rt_sender@example.com",
                           password: "password123", password_confirmation: "password123")
    @recipient = User.create!(username: "rt_recipient", email: "rt_recipient@example.com",
                              password: "password123", password_confirmation: "password123")
    @conversation = Conversation.find_or_create_between!(@sender, @recipient)
  end

  test "a new message broadcasts to the recipient's message stream" do
    assert_turbo_stream_broadcasts([ @conversation, @recipient.id, :messages ], count: 1) do
      @conversation.messages.create!(sender: @sender, body: "Grace and peace to you today.")
    end
  end

  test "the sender is not sent a duplicate broadcast (they get the echo in-request)" do
    assert_no_turbo_stream_broadcasts([ @conversation, @sender.id, :messages ]) do
      @conversation.messages.create!(sender: @sender, body: "Grace and peace to you today.")
    end
  end
end

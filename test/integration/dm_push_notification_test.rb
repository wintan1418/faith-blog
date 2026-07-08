# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# A direct message should fire a Web Push to the recipient's subscribed devices.
class DmPushNotificationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @sender = User.create!(username: "push_sender", email: "push_sender@example.com",
                           password: "password123", password_confirmation: "password123")
    @recipient = User.create!(username: "push_recipient", email: "push_recipient@example.com",
                              password: "password123", password_confirmation: "password123")
    @conversation = Conversation.find_or_create_between!(@sender, @recipient)
    @sub = @recipient.push_subscriptions.create!(
      endpoint: "https://push.example.com/abc123",
      p256dh_key: "test-p256dh",
      auth_key: "test-auth"
    )
  end

  def with_vapid
    ENV["VAPID_PUBLIC_KEY"]  = "test-public"
    ENV["VAPID_PRIVATE_KEY"] = "test-private"
    yield
  ensure
    ENV.delete("VAPID_PUBLIC_KEY")
    ENV.delete("VAPID_PRIVATE_KEY")
  end

  test "sending a DM pushes to the recipient's subscription, deep-linked to the chat" do
    sent = []
    with_vapid do
      WebPush.stub :payload_send, ->(**kwargs) { sent << kwargs } do
        perform_enqueued_jobs do
          @conversation.messages.create!(sender: @sender, body: "Grace and peace to you today.")
        end
      end
    end

    assert_equal 1, sent.size, "expected exactly one push to the recipient"
    assert_equal @sub.endpoint, sent.first[:endpoint]

    payload = JSON.parse(sent.first[:message])
    assert_match(/sent you a message/, payload["body"])
    assert_equal conversation_path(@conversation), payload["url"]
    # DM pushes collapse per conversation so a burst doesn't stack.
    assert_equal "brethreign-dm-#{@conversation.id}", payload["tag"]
  end

  test "no push is sent when VAPID keys are not configured" do
    sent = []
    # No with_vapid — keys absent, so the job should no-op.
    WebPush.stub :payload_send, ->(**kwargs) { sent << kwargs } do
      perform_enqueued_jobs do
        @conversation.messages.create!(sender: @sender, body: "Grace and peace to you today.")
      end
    end

    assert_empty sent
  end
end

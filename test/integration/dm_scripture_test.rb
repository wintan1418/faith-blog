# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Sharing a Bible verse inside a direct message.
class DmScriptureTest < ActionDispatch::IntegrationTest
  setup do
    @sender = User.create!(username: "verse_sender", email: "verse_sender@example.com",
                           password: "password123", password_confirmation: "password123")
    @recipient = User.create!(username: "verse_recipient", email: "verse_recipient@example.com",
                              password: "password123", password_confirmation: "password123")
    @conversation = Conversation.find_or_create_between!(@sender, @recipient)
  end

  # Stubbed because sending a verse message now broadcasts synchronously, which
  # renders the scripture card (a ScriptureLookup network call) inline.
  VERSE = { reference: "John 3:16", text: "For God so loved the world…", translation: "KJV" }.freeze

  test "a message can carry a shared verse with no body, and the reference is normalized" do
    sign_in @sender

    ScriptureLookup.stub :lookup, VERSE do
      assert_difference -> { @conversation.messages.count }, 1 do
        post conversation_messages_path(@conversation),
             params: { message: { scripture_ref: "please read John 3:16 tonight" } }
      end
    end

    message = @conversation.messages.order(:created_at).last
    assert message.has_scripture?
    assert_equal "John 3:16", message.scripture_ref
    assert message.body.blank?
  end

  test "the verse renders as a card in the thread" do
    ScriptureLookup.stub :lookup, VERSE do
      @conversation.messages.create!(sender: @sender, scripture_ref: "John 3:16")
      sign_in @sender
      get conversation_path(@conversation)
    end

    assert_response :success
    assert_select ".dm-scripture-card"
    assert_match "John 3:16", response.body
    assert_match(/God so loved/, response.body)
  end

  test "a junk reference with no body is rejected" do
    sign_in @sender

    assert_no_difference -> { @conversation.messages.count } do
      post conversation_messages_path(@conversation),
           params: { message: { scripture_ref: "not a verse at all" } }
    end
  end
end

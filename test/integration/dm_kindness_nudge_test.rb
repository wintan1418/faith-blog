# frozen_string_literal: true

require "test_helper"

# The kindness nudge wires the DM composer to the gentleness tone check.
class DmKindnessNudgeTest < ActionDispatch::IntegrationTest
  setup do
    @sender = User.create!(username: "nudge_sender", email: "nudge_sender@example.com",
                           password: "password123", password_confirmation: "password123")
    @recipient = User.create!(username: "nudge_recipient", email: "nudge_recipient@example.com",
                              password: "password123", password_confirmation: "password123")
    @conversation = Conversation.find_or_create_between!(@sender, @recipient)
  end

  test "the composer renders the nudge UI and wires the tone check on submit" do
    sign_in @sender
    get conversation_path(@conversation)

    assert_response :success
    assert_select ".dm-nudge"
    assert_select ".dm-nudge-soften"
    assert_select ".dm-nudge-send"
    assert_select "form#new_message[data-action*=?]", "dm-composer#onSubmit"
    assert_select "form#new_message[data-dm-composer-gentleness-url-value=?]", check_gentleness_posts_path
  end
end

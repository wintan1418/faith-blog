# frozen_string_literal: true

require "test_helper"

# Emergency 18 Nov: the inbox crashed for everyone who had chatted with a member
# who later deleted their account (the chat had no other person any more).
class InboxDeletedMemberTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @me = create_member("inbox_keeper", tour_completed_at: Time.current)
    @gone = create_member("inbox_leaver", tour_completed_at: Time.current)
    @friend = create_member("inbox_friend2", tour_completed_at: Time.current)
    @gone_chat = Conversation.find_or_create_between!(@me, @gone)
    Message.create!(conversation: @gone_chat, sender: @me, body: "Welcome home")
    Message.create!(conversation: Conversation.find_or_create_between!(@me, @friend), sender: @friend, body: "Peace")
    ConversationParticipant.where(user: @gone).delete_all # as after the account is deleted
  end

  test "the inbox still opens and leaves the deleted member's chat out" do
    sign_in @me
    get conversations_path
    assert_response :success
    assert_match "inbox_friend2", response.body
  end

  test "opening that chat explains the member deleted their account" do
    sign_in @me
    get conversation_path(@gone_chat)
    assert_response :success
    assert_match "This member deleted their account", response.body
  end
end

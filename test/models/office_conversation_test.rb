# frozen_string_literal: true

require "test_helper"

class OfficeConversationTest < ActiveSupport::TestCase
  setup do
    @admin = create_member("office_model_#{SecureRandom.hex(3)}", role: :admin)
    @conversation = @admin.office_conversations.create!
  end

  test "a new thread is named after its first message, once" do
    @conversation.title_from!("## Draft a **breath** for Sunday morning about rest and renewal in the Lord\nmore")
    assert_equal "Draft a breath for Sunday morning about rest and renewal in…", @conversation.title

    @conversation.title_from!("Something else")
    assert_match "Draft a breath", @conversation.title
  end

  test "busy only while thinking and not stale" do
    assert_not @conversation.busy?
    @conversation.update!(thinking: true)
    assert @conversation.busy?
    @conversation.update_columns(updated_at: 11.minutes.ago)
    assert_not @conversation.busy?, "a reply that never finished must not lock the thread"
  end

  test "deleting the admin deletes their conversations and messages" do
    @conversation.messages.create!(role: :user, content: "Hi")
    @admin.destroy
    assert_not OfficeConversation.exists?(@conversation.id)
    assert_equal 0, OfficeMessage.where(office_conversation_id: @conversation.id).count
  end

  test "the briefing starts from the default file and is created once" do
    OfficeBriefing.delete_all
    briefing = OfficeBriefing.current
    assert_match "Chief Steward", briefing.body
    assert_no_match "350,000", briefing.body, "private fundraising figures stay out of the public repository"
    assert_equal briefing, OfficeBriefing.current
    assert_equal 1, OfficeBriefing.count
  end
end

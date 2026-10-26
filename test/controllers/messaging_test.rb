# frozen_string_literal: true

require "test_helper"

# The LinkedIn-style inbox: list, filters, new message, and the conversation view.
class MessagingTest < ActionDispatch::IntegrationTest
  APP_UA = "Brethreign/1.0.3; Hotwire Native Android; Turbo Native Android"

  def make_user(name)
    User.create!(username: name, email: "#{name.downcase}@example.com", password: "password123", password_confirmation: "password123")
  end

  def connect(a, b)
    # Skip the Brethren Card requirement: these tests are about messaging, not connecting.
    ConnectionRequest.new(sender: a, receiver: b, status: :accepted).save!(validate: false)
  end

  def say(conversation, sender, body, at:)
    conversation.messages.create!(sender: sender, body: body).tap do |m|
      m.update_columns(created_at: at, updated_at: at)
      conversation.update_columns(last_message_at: at)
    end
  end

  setup do
    @me = make_user("Faithful")
    @maria = make_user("MariaHope")
    @james = make_user("PastorJames")
    connect(@me, @maria)
    connect(@james, @me)
    @with_maria = Conversation.find_or_create_between!(@me, @maria)
    say(@with_maria, @maria, "Would you pray with me?", at: 2.hours.ago)
    @with_james = Conversation.find_or_create_between!(@me, @james)
    say(@with_james, @me, "See you Sunday", at: 3.days.ago)
    @with_james.participant_for(@me).update!(last_read_at: Time.current)
    sign_in @me
  end

  test "the list shows people, previews, and who has unread messages" do
    get conversations_path

    assert_response :success
    assert_select ".msg-row.is-unread .msg-row-name", text: "MariaHope"
    assert_select ".msg-row-preview", text: "You: See you Sunday"
    assert_select ".msg-filter.is-active", text: "All"
  end

  test "the Unread filter keeps only conversations waiting on you" do
    get conversations_path(filter: "unread")

    assert_select ".msg-row", count: 1
    assert_select ".msg-row-name", text: "MariaHope"
  end

  test "chats that were opened but never written in stay out of the list" do
    Conversation.find_or_create_between!(@me, make_user("Quiet"))
    get conversations_path

    assert_select ".msg-row-name", text: "Quiet", count: 0
  end

  test "new message lists each connection once" do
    connect(@maria, @me) # connected both ways
    get new_conversation_path

    assert_response :success
    assert_select ".msg-row-name", text: "MariaHope", count: 1
    assert_select ".msg-row-name", text: "PastorJames", count: 1
  end

  test "a conversation groups messages and shows day dividers" do
    say(@with_maria, @maria, "Thank you so much", at: 2.hours.ago + 1.minute)
    say(@with_maria, @me, "Praying for you", at: 1.hour.ago)
    get conversation_path(@with_maria)

    assert_response :success
    assert_select ".msg-day", text: "Today"
    assert_select ".msg-item", count: 3
    assert_select ".msg-item.starts-group", count: 2, message: "Maria's two quick messages share one header"
    assert_select ".msg-receipt", text: /Sent/
  end

  test "in the app the top bar says Messaging, not the person's name" do
    get conversation_path(@with_maria), headers: { "User-Agent" => APP_UA }

    assert_select "title", text: "Messaging"
    assert_select ".msg-thread-name", text: "MariaHope"
  end

  test "sending a message updates the thread and the receipt" do
    post conversation_messages_path(@with_maria), params: { message: { body: "Amen" } }, as: :turbo_stream

    assert_response :success
    assert_match %r{<turbo-stream action="append" target="messages">}, response.body
    assert_match %r{<turbo-stream action="replace" target="read_receipt">}, response.body
  end

  test "opening a conversation clears its chat notifications" do
    @with_maria.messages.create!(sender: @maria, body: "Are you there?")
    assert @me.notifications.unread.direct_message.exists?

    get conversation_path(@with_maria)

    assert_not @me.notifications.unread.direct_message.exists?
  end

  test "long chats open with the latest 50 and load earlier ones on request" do
    60.times { |i| say(@with_maria, @maria, "Message #{i}", at: (120 - i).minutes.ago) }
    get conversation_path(@with_maria)

    assert_select ".msg-item", count: 50
    assert_select "#load_earlier a", text: "Load earlier messages"
    assert_no_match "Message 9<", response.body, "the oldest ones wait"

    first_shown = @with_maria.messages.visible.order(created_at: :desc).limit(50).last
    get earlier_conversation_path(@with_maria, before: first_shown.id), as: :turbo_stream

    assert_response :success
    assert_match "Would you pray with me?", response.body, "the very first message comes back"
    assert_match %r{<turbo-stream action="replace" target="message_#{first_shown.id}">}, response.body
  end

  test "the list shows previews and unread counts from batched queries" do
    say(@with_maria, @maria, "Second line", at: 1.hour.ago)
    get conversations_path

    assert_select ".msg-row.is-unread .msg-row-unread", text: "2"
    assert_select ".msg-row-preview", text: "Second line"
  end
end

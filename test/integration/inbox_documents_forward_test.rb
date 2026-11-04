# frozen_string_literal: true

require "test_helper"

# Inbox: send documents; share or forward a message.
class InboxDocumentsForwardTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier

  setup do
    @pass = SecureRandom.base58(16)
    @ada = User.create!(username: "ada_docs", email: "ada-docs@example.com", password: @pass, password_confirmation: @pass)
    @ben = User.create!(username: "ben_docs", email: "ben-docs@example.com", password: @pass, password_confirmation: @pass)
    @cy  = User.create!(username: "cy_docs", email: "cy-docs@example.com", password: @pass, password_confirmation: @pass)
    @chat = Conversation.find_or_create_between!(@ada, @ben)
    @other_chat = Conversation.find_or_create_between!(@ada, @cy)
  end

  def pdf(name = "notes.pdf", body: "%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF\n")
    Rack::Test::UploadedFile.new(StringIO.new(body), "application/pdf", original_filename: name)
  end

  # ── Documents ──

  test "a document can be sent in a chat and shows as a file card" do
    sign_in @ada
    post conversation_messages_path(@chat), params: { message: { body: "", documents: [ pdf ] } }

    message = @chat.messages.order(:id).last
    assert message.has_documents?
    assert_equal "📄 notes.pdf", message.quote_snippet

    get conversation_path(@chat)
    assert_select "##{dom_id(message)} a.msg-doc .msg-doc-name", text: "notes.pdf"
    assert_select "##{dom_id(message)} .msg-doc-meta", text: /PDF ·/
  end

  test "only real documents are accepted" do
    message = @chat.messages.new(sender: @ada, body: "")
    message.documents.attach(io: StringIO.new("<script>alert(1)</script>"), filename: "page.pdf", content_type: "text/html")
    assert_not message.valid?, "an HTML page named .pdf is refused"

    message = @chat.messages.new(sender: @ada, body: "")
    message.documents.attach(io: StringIO.new("MZ\x90\x00"), filename: "setup.exe", content_type: "application/octet-stream")
    assert_not message.valid?
  end

  test "documents over the size limit are refused" do
    message = @chat.messages.new(sender: @ada, body: "")
    message.documents.attach(io: StringIO.new("x"), filename: "big.pdf", content_type: "application/pdf")
    message.documents.first.blob.byte_size = Message::DOCUMENT_MAX_BYTES + 1
    assert_not message.valid?
    assert_match(/too large/, message.errors.full_messages.join)
  end

  test "the composer has an attach button for documents" do
    sign_in @ada
    get conversation_path(@chat)
    assert_select "input[type=file][name='message[documents][]'][accept*='.pdf']"
  end

  # ── Forward ──

  test "a message can be forwarded to another chat, files and all" do
    original = @chat.messages.new(sender: @ben, body: "Prayer points for Sunday")
    original.documents.attach(io: StringIO.new("%PDF-1.4"), filename: "points.pdf", content_type: "application/pdf")
    original.save!
    sign_in @ada

    get forward_conversation_message_path(@chat, original)
    assert_response :success
    assert_select "input[name='conversation_ids[]'][value=?]", @other_chat.id.to_s

    post forward_conversation_message_path(@chat, original), params: { conversation_ids: [ @other_chat.id ] }
    assert_redirected_to conversation_path(@other_chat)

    copy = @other_chat.messages.order(:id).last
    assert copy.forwarded?
    assert_equal @ada, copy.sender
    assert_equal "Prayer points for Sunday", copy.body
    assert_equal original.documents.first.blob, copy.documents.first.blob, "the same stored file, not a re-upload"

    get conversation_path(@other_chat)
    assert_select "##{dom_id(copy)} .msg-forwarded", text: /Forwarded/
  end

  test "messages can't be forwarded into someone else's chat" do
    strangers = Conversation.find_or_create_between!(@ben, @cy)
    message = @chat.messages.create!(sender: @ben, body: "Hello")
    sign_in @ada

    post forward_conversation_message_path(@chat, message), params: { conversation_ids: [ strangers.id ] }
    assert_equal 0, strangers.messages.count
  end

  test "a deleted message can't be forwarded" do
    message = @chat.messages.create!(sender: @ben, body: "Gone", deleted_at: Time.current)
    sign_in @ada
    post forward_conversation_message_path(@chat, message), params: { conversation_ids: [ @other_chat.id ] }
    assert_equal 0, @other_chat.messages.count
  end

  test "forwarding stops at five chats" do
    message = @chat.messages.create!(sender: @ben, body: "Pass it on")
    chats = Array.new(7) do |i|
      friend = User.create!(username: "friend#{i}_docs", email: "friend#{i}-docs@example.com", password: @pass, password_confirmation: @pass)
      Conversation.find_or_create_between!(@ada, friend)
    end
    sign_in @ada
    post forward_conversation_message_path(@chat, message), params: { conversation_ids: chats.map(&:id) }
    assert_equal Message::FORWARD_LIMIT, Message.where(forwarded: true).count
  end

  # ── Share ──

  test "messages offer Share and Forward" do
    message = @chat.messages.create!(sender: @ben, body: "Grace and peace")
    sign_in @ada
    get conversation_path(@chat)
    assert_select "##{dom_id(message)} .msg-actions [data-controller='message-share'][data-message-share-text-value='Grace and peace']"
    assert_select "##{dom_id(message)} .msg-actions a[href=?]", forward_conversation_message_path(@chat, message)
  end
end

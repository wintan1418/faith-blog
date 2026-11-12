# frozen_string_literal: true

require "test_helper"

# Files sent in a chat download from our own site under their original name,
# and only for the people in that conversation.
class InboxFileDownloadsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier

  PPTX = "application/vnd.openxmlformats-officedocument.presentationml.presentation"

  setup do
    @pass = SecureRandom.base58(16)
    @ada = User.create!(username: "ada_dl", email: "ada-dl@example.com", password: @pass, password_confirmation: @pass)
    @ben = User.create!(username: "ben_dl", email: "ben-dl@example.com", password: @pass, password_confirmation: @pass)
    @cy  = User.create!(username: "cy_dl", email: "cy-dl@example.com", password: @pass, password_confirmation: @pass)
    @chat = Conversation.find_or_create_between!(@ada, @ben)

    @message = @chat.messages.new(sender: @ada, body: "")
    @message.documents.attach(io: StringIO.new("%PDF-1.4\n%%EOF\n"), filename: "Quarterly Report.pdf", content_type: "application/pdf")
    @message.documents.attach(io: StringIO.new("PK\x03\x04slides"), filename: "Sermon slides.pptx", content_type: PPTX)
    @message.images.attach(io: file_fixture_or_jpeg, filename: "IMG_2041.jpeg", content_type: "image/jpeg")
    @message.save!
  end

  def file_fixture_or_jpeg
    StringIO.new("\xFF\xD8\xFF\xE0\x00\x10JFIF\x00jpegbytes\xFF\xD9".b)
  end

  def download_path(attachment, message: @message)
    conversation_message_file_path(message.conversation_id, message, attachment.id, filename: attachment.filename.to_s)
  end

  # Streamed responses don't refresh the session cookie, so sign in before each request.
  test "a participant downloads each file under its original name and type" do
    { @message.documents.first => [ "Quarterly Report.pdf", "application/pdf", "%PDF-1.4\n%%EOF\n" ],
      @message.documents.second => [ "Sermon slides.pptx", PPTX, "PK\x03\x04slides" ],
      @message.images.first => [ "IMG_2041.jpeg", "image/jpeg", file_fixture_or_jpeg.string ] }.each do |attachment, (name, type, body)|
      sign_in @ben
      get download_path(attachment)

      assert_response :success
      disposition = response.headers["Content-Disposition"]
      assert disposition.start_with?("attachment"), "#{name}: #{disposition}"
      assert_includes disposition, %(filename="#{name}")
      assert_includes disposition, "filename*=UTF-8''#{ERB::Util.url_encode(name)}"
      assert_equal type, response.media_type
      assert_equal body.b, response.body.b
    end
  end

  test "the sender can download their own file too" do
    sign_in @ada
    get download_path(@message.documents.first)
    assert_response :success
    assert_includes response.headers["Content-Disposition"], "Quarterly Report.pdf"
  end

  test "someone outside the conversation gets a 404" do
    sign_in @cy
    get download_path(@message.documents.first)
    assert_response :not_found
    assert_nil response.headers["Content-Disposition"]
  end

  test "a file from another conversation can't be fetched through a chat you're in" do
    other_chat = Conversation.find_or_create_between!(@ben, @cy)
    secret = other_chat.messages.new(sender: @cy, body: "")
    secret.documents.attach(io: StringIO.new("%PDF-1.4 secret"), filename: "secret.pdf", content_type: "application/pdf")
    secret.save!

    sign_in @ada
    # Ada's own chat and message, but the attachment id belongs to Ben and Cy's chat.
    get conversation_message_file_path(@chat, @message, secret.documents.first.id, filename: "secret.pdf")
    assert_response :not_found
    # And Ada can't use Ben and Cy's chat id either.
    sign_in @ada
    get download_path(secret.documents.first, message: secret)
    assert_response :not_found
  end

  test "signed-out visitors are sent to sign in" do
    get download_path(@message.documents.first), headers: { "Accept" => "text/html" }
    assert_redirected_to new_user_session_path

    get download_path(@message.documents.first)
    assert_response :unauthorized
    assert_nil response.headers["Content-Disposition"]
  end

  test "deleted or removed messages no longer hand out their files" do
    sign_in @ben
    @message.update_columns(removed_at: Time.current)
    get download_path(@message.documents.first)
    assert_response :not_found

    @message.update_columns(removed_at: nil, deleted_at: Time.current)
    sign_in @ben
    get download_path(@message.documents.first)
    assert_response :not_found
  end

  test "the chat links photos and documents to the download route" do
    sign_in @ben
    get conversation_path(@chat)

    doc = @message.documents.first
    assert_select "##{dom_id(@message)} a.msg-doc[href=?][download=?]", download_path(doc), "Quarterly Report.pdf"
    assert_select "##{dom_id(@message)} a.msg-doc[href=?]", download_path(@message.documents.second)
    assert_select "##{dom_id(@message)} img.msg-image[data-download=?]", download_path(@message.images.first)
    assert_select "##{dom_id(@message)} a.msg-doc[href*='/rails/active_storage/']", count: 0
  end
end

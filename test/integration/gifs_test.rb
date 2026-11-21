# frozen_string_literal: true

require "test_helper"

# GIFs from Klipy in chats and comments: the private JSON endpoint, the
# button (only with a key), sending, the CDN allowlist, and moderation.
class GifsTest < ActionDispatch::IntegrationTest
  include KlipyStubs
  include Turbo::Broadcastable::TestHelper

  GIF = { gif_url: "https://static.klipy.com/ii/abc/md.gif", gif_width: "320", gif_height: "240", gif_title: "Praise hands" }.freeze

  setup do
    with_klipy_key
    seen = { tour_completed_at: Time.current, welcomed_at: Time.current }
    @me = create_member("gif_sender", **seen)
    @friend = create_member("gif_friend", **seen)
    ConnectionRequest.new(sender: @me, receiver: @friend, status: :accepted).save!(validate: false)
    @chat = Conversation.find_or_create_between!(@me, @friend)
    room = Room.create!(name: "Encouragement", description: "x", room_type: :general, is_public: true)
    @post = Post.create!(user: @friend, room: room, title: "Answered prayer", content: "God came through",
                         status: :published, moderation_status: :approved)
  end

  teardown { without_klipy_key }

  # ── The endpoint ─────────────────────────────────────────────────────

  test "signed-out visitors can't use the endpoint" do
    Klipy.stub(:http_get, ->(_uri) { flunk "Klipy must not be called" }) do
      get gifs_path(q: "joy"), as: :json
      assert_response :unauthorized
      get trending_gifs_path, as: :json
      assert_response :unauthorized
    end
  end

  test "search and trending return only id, preview, url, size and title" do
    sign_in @me
    Klipy.stub(:http_get, ->(_uri) { klipy_response(klipy_payload) }) do
      get gifs_path(q: "praise"), as: :json
    end
    assert_response :success
    results = response.parsed_body["results"]
    assert_equal %w[praise-hands amen], results.map { |r| r["id"] }
    assert_equal %w[height id preview_url title url width], results.first.keys.sort
    assert_no_match "test-klipy-key", response.body
    assert_equal "private, no-store", response.headers["Cache-Control"]

    Klipy.stub(:http_get, ->(_uri) { klipy_response(klipy_payload) }) { get trending_gifs_path, as: :json }
    assert_response :success
    assert_equal 2, response.parsed_body["results"].size
  end

  test "Klipy being down is a friendly error, not a crash" do
    sign_in @me
    Klipy.stub(:http_get, ->(_uri) { raise Net::OpenTimeout }) { get trending_gifs_path, as: :json }
    assert_response :bad_gateway
    assert_equal [], response.parsed_body["results"]
    assert response.parsed_body["error"].present?
  end

  test "the endpoint is rate limited per member" do
    sign_in @me
    Klipy.stub(:http_get, ->(_uri) { klipy_response(klipy_payload) }) do
      40.times { get gifs_path(q: "joy"), as: :json }
      assert_response :success
      get gifs_path(q: "joy"), as: :json
      assert_response :too_many_requests

      # Someone else still has their own allowance.
      sign_in @friend
      get gifs_path(q: "joy"), as: :json
      assert_response :success
    end
  end

  test "without a key the endpoint is off" do
    without_klipy_key
    sign_in @me
    get gifs_path(q: "joy"), as: :json
    assert_response :not_found
  end

  # ── The button ───────────────────────────────────────────────────────

  test "no key means no GIF button in the chat or on a post" do
    without_klipy_key
    sign_in @me
    get conversation_path(@chat)
    assert_response :success
    assert_select ".msg-compose-tools .msg-tool--emoji"
    assert_select "[data-controller~='gif-picker']", count: 0
    get post_path(@post)
    assert_response :success
    assert_select "[data-controller~='gif-picker']", count: 0
  end

  test "with a key the GIF button shows in the chat and the comment box" do
    sign_in @me
    get conversation_path(@chat)
    assert_select ".msg-compose-tools [data-controller~='gif-picker'][data-gif-picker-scope-value='message'] button.msg-tool--gif"
    get post_path(@post)
    assert_select "#comment_form [data-controller~='gif-picker'][data-gif-picker-scope-value='comment']"
    assert_no_match "test-klipy-key", response.body
  end

  # ── Messages ─────────────────────────────────────────────────────────

  test "sending a GIF on its own puts it in the chat, previews and notifications" do
    sign_in @me
    assert_turbo_stream_broadcasts([ @chat, @friend.id, :messages ], count: 1) do
      post conversation_messages_path(@chat), params: { message: { body: "" }.merge(GIF) }, as: :turbo_stream
    end
    assert_response :success

    message = @chat.messages.last
    assert message.has_gif?
    assert_equal "", message.body
    assert_equal [ 320, 240 ], [ message.gif_width, message.gif_height ]
    assert_select "img.msg-gif[src='#{GIF[:gif_url]}'][alt='Praise hands'][loading='lazy'][width='240'][height='180']"
    assert_equal "GIF", message.quote_snippet

    # The broadcast partial (no request) renders it too.
    html = ApplicationController.render(partial: "conversations/message", locals: { message: message, viewer_id: @friend.id })
    assert_includes html, %(src="#{GIF[:gif_url]}")

    notification = @friend.notifications.direct_message.last
    assert_equal "gif_sender sent you a GIF", notification.message

    sign_in @friend
    get conversations_path
    assert_select ".msg-row-preview", text: "Sent a GIF"
  end

  test "a GIF can come with words" do
    sign_in @me
    post conversation_messages_path(@chat), params: { message: { body: "This is me today" }.merge(GIF) }, as: :turbo_stream
    assert_response :success
    assert_equal "This is me today", @chat.messages.last.body
    assert @chat.messages.last.has_gif?
  end

  test "only Klipy's CDN is allowed" do
    sign_in @me
    [ "https://evil.example/x.gif", "http://static.klipy.com/x.gif", "https://static.klipy.com.evil.example/x.gif", "javascript:alert(1)" ].each do |url|
      assert_no_difference -> { Message.count } do
        post conversation_messages_path(@chat), params: { message: { body: "" }.merge(GIF).merge(gif_url: url) }, as: :turbo_stream
      end
      assert_response :unprocessable_entity
    end
  end

  test "a GIF with an offensive title is refused" do
    sign_in @me
    assert_no_difference -> { Message.count } do
      post conversation_messages_path(@chat), params: { message: { body: "" }.merge(GIF).merge(gif_title: "shit happens") }, as: :turbo_stream
    end
    assert_response :unprocessable_entity
  end

  test "without a key, GIF fields are ignored" do
    without_klipy_key
    sign_in @me
    post conversation_messages_path(@chat), params: { message: { body: "Hello" }.merge(GIF) }, as: :turbo_stream
    assert_response :success
    assert_not @chat.messages.last.has_gif?
  end

  test "moderation handles a GIF-only message" do
    message = @chat.messages.create!(sender: @me, body: "", **GIF)
    message.update_columns(moderated_at: nil)
    assert_nothing_raised { MessageModerationJob.perform_now(message) }
    assert message.reload.moderated_at.present?
    assert_not message.removed?

    # A stranger's first GIF-only messages go through the same job.
    stranger = create_member("gif_stranger")
    chat = Conversation.find_or_create_between!(stranger, @me)
    lonely = chat.messages.create!(sender: stranger, body: "", **GIF)
    lonely.update_columns(moderated_at: nil)
    assert_nothing_raised { MessageModerationJob.perform_now(lonely) }
    assert_not lonely.reload.removed?
  end

  test "a GIF message forwards with its GIF" do
    message = @chat.messages.create!(sender: @me, body: "", **GIF)
    other = Conversation.find_or_create_between!(@me, create_member("gif_third"))
    copy = message.forward_to(other, by: @me)
    assert copy.persisted?
    assert_equal GIF[:gif_url], copy.gif_url
  end

  # ── Comments ─────────────────────────────────────────────────────────

  test "a GIF on its own is a comment" do
    sign_in @me
    assert_difference -> { @post.comments.count }, 1 do
      post post_comments_path(@post), params: { comment: { content: "" }.merge(GIF) }
    end
    comment = @post.comments.last
    assert comment.has_gif?
    assert comment.moderation_approved?
    assert_nothing_raised { AiModerationReviewJob.perform_now(comment) }

    get post_path(@post)
    assert_select "img.cm-gif[src='#{GIF[:gif_url]}'][alt='Praise hands'][loading='lazy']"
  end

  test "a GIF reply to a comment" do
    parent = Comment.create!(post: @post, user: @friend, content: "Praise God!", moderation_status: :approved)
    sign_in @me
    assert_difference -> { parent.replies.count }, 1 do
      post reply_post_comment_path(@post, parent), params: { comment: { content: "" }.merge(GIF) }
    end
    assert parent.replies.last.has_gif?
  end

  test "comments refuse GIFs from anywhere else, and empty comments still fail" do
    sign_in @me
    assert_no_difference -> { Comment.count } do
      post post_comments_path(@post), params: { comment: { content: "" }.merge(GIF).merge(gif_url: "https://evil.example/x.gif") }
      post post_comments_path(@post), params: { comment: { content: "" } }
    end
  end
end

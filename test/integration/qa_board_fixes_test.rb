# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Fixes for the QA board's "To Do (Bugs)" list (29 Oct 2026).
class QaBoardFixesTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @pass = SecureRandom.base58(16)
    @ada = User.create!(username: "ada_qa", email: "ada-qa@example.com", password: @pass, password_confirmation: @pass)
    @ben = User.create!(username: "ben_qa", email: "ben-qa@example.com", password: @pass, password_confirmation: @pass)
  end

  DRAFT = "I have been so anxious about my job lately and I do not know where to turn. Pray for me."

  # ── Suggest scripture / Check tone keep working when the AI doesn't ──

  test "suggest scripture answers from the draft's themes when the AI fails" do
    sign_in @ada
    failing = ->(**) { raise Ai::Moderation::Client::ApiError, "gemini 503" }
    Ai::Composer::ScriptureSuggester.stub :call, failing do
      ScriptureLookup.stub :lookup, nil do
        post suggest_scripture_posts_path, params: { content: DRAFT }, as: :json
      end
    end

    assert_response :success
    body = response.parsed_body
    assert body["ok"]
    assert_includes body["verses"].map { |v| v["reference"] }, "Philippians 4:6-7"
  end

  test "check tone answers from the word filter when the AI fails" do
    sign_in @ada
    failing = ->(**) { raise Net::ReadTimeout }
    Ai::Composer::GentlenessCheck.stub :call, failing do
      post check_gentleness_posts_path, params: { content: "You are such an idiot for saying that, honestly." }, as: :json
    end

    assert_response :success
    assert_equal "harsh", response.parsed_body["tone"]
  end

  test "fallback scripture picks a verse that fits" do
    refs = Ai::Composer::Fallback.scripture("God would that all of Israel were prophets").map(&:reference)
    assert_includes refs, "Numbers 11:29"
    assert_equal 3, Ai::Composer::Fallback.scripture("hello there friends").size
  end

  test "a timed-out AI call becomes an API error the callers handle" do
    provider = Ai::Moderation::Providers::Gemini.new(api_key: "test-key")
    http = Net::HTTP.new("example.com", 443)
    def http.request(*) = raise(Net::OpenTimeout)
    Net::HTTP.stub :new, http do
      assert_raises(Ai::Moderation::Client::ApiError) { provider.call(system: "s", user: "u") }
    end
  end

  # ── Connection requests: a way to find people ──

  test "connection pages link to finding brethren" do
    sign_in @ada
    get connection_requests_path
    assert_select "a[href=?]", people_path, text: "Find brethren"
    get my_connections_path
    assert_select "a[href=?]", people_path, text: "Find brethren"
  end

  # ── Scheduling uses the writer's own time zone ──

  test "a schedule sent with a time zone is saved at the right moment" do
    sign_in @ada
    room = Room.create!(name: "QA Room", description: "x", is_public: true)
    at = 2.hours.from_now.change(sec: 0)
    lagos = at.in_time_zone("Africa/Lagos").iso8601 # e.g. 2026-10-29T21:00:00+01:00

    post posts_path, params: { post: { title: "Later", content: "A breath for later.", room_id: room.id,
                                       status: "published", scheduled_for: lagos } }

    scheduled = Post.order(:id).last
    assert scheduled.scheduled?
    assert_equal at.utc, scheduled.scheduled_for.utc
    assert_match(/goes live in about 2 hours/i, flash[:notice])
  end

  test "the composer's schedule picker sends its time with a time zone" do
    sign_in @ada
    get new_post_path
    assert_select "[data-controller~=schedule-field] input[type=hidden][name=?]", "post[scheduled_for]"
    assert_select "[data-controller~=schedule-field] input[type=datetime-local]:not([name])"
  end

  # ── Reply to one message in a chat ──

  test "a message can reply to another and shows the quote" do
    convo = Conversation.find_or_create_between!(@ada, @ben)
    original = convo.messages.create!(sender: @ben, body: "Are you coming to the vigil on Friday?")
    sign_in @ada

    post conversation_messages_path(convo), params: { message: { body: "Yes, I'll be there", reply_to_id: original.id } }

    reply = convo.messages.order(:id).last
    assert_equal original, reply.reply_to
    get conversation_path(convo)
    assert_select "##{ActionView::RecordIdentifier.dom_id(reply)} a.msg-quote[href=?]", "##{ActionView::RecordIdentifier.dom_id(original)}" do
      assert_select ".msg-quote-name", text: @ben.display_name
      assert_select ".msg-quote-text", text: /vigil on Friday/
    end
    assert_select ".msg-action--reply[data-reply-id=?]", original.id.to_s
  end

  test "you can't reply to a message from another chat" do
    carl = User.create!(username: "carl_qa", email: "carl-qa@example.com", password: @pass, password_confirmation: @pass)
    other = Conversation.find_or_create_between!(@ben, carl).messages.create!(sender: carl, body: "Private")
    convo = Conversation.find_or_create_between!(@ada, @ben)

    message = convo.messages.build(sender: @ada, body: "Hi", reply_to: other)
    assert_not message.valid?
    assert message.errors[:reply_to].any?
  end

  # ── Password reset link while signed in ──

  test "a reset link opens the reset form even when signed in" do
    token = @ada.send_reset_password_instructions
    sign_in @ada

    get edit_user_password_path(reset_password_token: token)

    assert_response :success
    assert_select "input[name=?]", "user[password]"

    put user_password_path, params: { user: { reset_password_token: token, password: "#{@pass}x" } }
    assert @ada.reload.valid_password?("#{@pass}x")
  end
end

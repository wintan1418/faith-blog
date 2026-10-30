# frozen_string_literal: true

require "test_helper"

# Fixes for the QA board's "To Do (Bugs)" list (30 Oct 2026).
class QaBoardFixesOct30Test < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier

  setup do
    @pass = SecureRandom.base58(16)
    @ada = User.create!(username: "ada_qa30", email: "ada-qa30@example.com", password: @pass, password_confirmation: @pass)
    @ben = User.create!(username: "ben_qa30", email: "ben-qa30@example.com", password: @pass, password_confirmation: @pass)
  end

  # ── Voice notes get an options button; chat reactions have no count ──

  test "a voice note has its own options button and chat reactions show no count" do
    convo = Conversation.find_or_create_between!(@ada, @ben)
    voice = convo.messages.new(sender: @ben, body: "")
    voice.voice_note.attach(io: StringIO.new("RIFF....WAVEfmt "), filename: "note.webm", content_type: "audio/webm")
    voice.save!(validate: false)
    voice.likes.create!(user: @ada, reaction_type: :love, reaction_emoji: "❤️")
    sign_in @ada

    get conversation_path(convo)

    assert_select "##{dom_id(voice)} .msg-voice-row button.msg-more[data-action~='message-menu#toggleFromButton']"
    assert_select "##{dom_id(voice)} .msg-reactions .msg-reaction", text: /❤️/
    assert_select "##{dom_id(voice)} .msg-reaction-count", count: 0
  end

  # ── Reacting on a breath's own page keeps that page's bar ──

  test "reacting returns the breath page's own reaction bar" do
    room = Room.create!(name: "QA30 Room", description: "x", is_public: true)
    breath = Post.create!(title: "Holy water", content: "Come to the Fountain.", room: room, user: @ben, status: "published")
    sign_in @ada

    get post_path(breath)
    assert_select "##{dom_id(breath, :reactions_bar)} .post-reactions-left[data-controller~='emoji-reactions']"

    post likes_path(likeable_type: "Post", likeable_id: breath.id, reaction_emoji: "🔥"),
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_select "turbo-stream[action='replace'][target='#{dom_id(breath, :reactions_bar)}']"
  end

  # ── Alerts page reflects reads without a reload ──

  test "the alerts page is never shown from a stale copy and wires instant updates" do
    Notification.create!(user: @ada, actor: @ben, notification_type: :new_follower, notifiable: @ben)
    sign_in @ada

    get notifications_path

    assert_select "meta[name='turbo-cache-control'][content='no-cache']"
    assert_select "[data-controller~='notifications-page'] a.fc-notifrow[data-action~='notifications-page#open']"
    assert_select "form[data-action~='submit->notifications-page#markAll']"
  end

  # ── Invites show "Accepted" however the person joined ──

  test "an invite is accepted when that email signs up any way" do
    invite = Invitation.create!(inviter: @ada, email: "New.Friend@Example.com")
    assert_nil invite.accepted_at

    friend = User.create!(username: "new_friend30", email: "new.friend@example.com", password: @pass, password_confirmation: @pass)

    invite.reload
    assert invite.accepted?
    assert_equal friend, invite.invited_user
  end
end

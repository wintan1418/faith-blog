# frozen_string_literal: true

require "application_system_test_case"

# Two inbox bugs from the Android testers:
#  - Send took 1-2s (sometimes more taps): a longer message was held back
#    while an AI tone check ran. Send now never waits on that check.
#  - New messages didn't show in Recent chats until the inbox was refreshed:
#    the list had no live updates. A new message now moves its chat to the
#    top of each participant's open list.
class InboxLiveTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  APP_USER_AGENT = "Brethreign/1.0.8; Hotwire Native Android; Turbo Native Android; " \
                   "Mozilla/5.0 (Linux; Android 16; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) " \
                   "Version/4.0 Chrome/133.0.0.0 Mobile Safari/537.36"

  driven_by :selenium, using: :headless_chrome, screen_size: [ 412, 900 ], options: { name: :android_inbox_live } do |options|
    options.add_argument("--user-agent=#{APP_USER_AGENT}")
  end

  LONG_TEXT = "Thank you so much sir, I will definitely do it this week"

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    seen = { welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i,
             tour_completed_at: Time.current, onboarding_dismissed_at: Time.current }
    @me = create_member("inbox_me", **seen)
    @friend = create_member("inbox_friend", **seen)
    @other = create_member("inbox_other", **seen)
    @chat = Conversation.find_or_create_between!(@me, @friend)
    @older_chat = Conversation.find_or_create_between!(@me, @other)
    Message.create!(conversation: @older_chat, sender: @other, body: "Peace be with you", created_at: 2.hours.ago)
    Message.create!(conversation: @chat, sender: @friend, body: "Hello brother", created_at: 3.hours.ago)
    login_as @me, scope: :user
  end

  teardown { Warden.test_reset! }

  # Make the tone check answer however the test needs, in the page.
  def fake_tone_check(js_response)
    page.execute_script(<<~JS)
      const realFetch = window.fetch
      window.fetch = (url, opts) => String(url).includes("check_gentleness")
        ? #{js_response}
        : realFetch(url, opts)
    JS
  end

  test "Send goes straight away even while the tone check is still thinking" do
    visit conversation_path(@chat)
    fake_tone_check("new Promise(() => {})") # never answers
    find("#new_message textarea").fill_in(with: LONG_TEXT)
    sleep 1.5 # the background tone check has started and is hanging
    find("#new_message [data-dm-composer-target='sendBtn']").click

    assert_selector "#messages", text: LONG_TEXT, wait: 1.5
  end

  # Moderation: protect people without policing them (082df2b) — chats no
  # longer run an automatic tone check, so even words the checker would call
  # harsh send as written, with no kindness nudge in the way.
  test "chats send as written: no tone check, no kindness nudge" do
    visit conversation_path(@chat)
    page.execute_script(<<~JS)
      window.__toneChecks = 0
      const realFetch = window.fetch
      window.fetch = (url, opts) => {
        if (String(url).includes("check_gentleness")) {
          window.__toneChecks++
          return Promise.resolve(new Response(JSON.stringify({ ok: true, tone: "harsh", confidence: 0.9,
            nudge: "This could wound.", suggestion: "" }), { headers: { "Content-Type": "application/json" } }))
        }
        return realFetch(url, opts)
      }
    JS
    find("#new_message textarea").fill_in(with: LONG_TEXT)
    find("#new_message [data-dm-composer-target='sendBtn']").click

    assert_selector "#messages", text: LONG_TEXT
    assert_no_selector ".dm-nudge", visible: true
    assert_equal 0, page.evaluate_script("window.__toneChecks"), "no tone check is made in chats"
  end

  test "a new message moves its chat to the top of the open inbox without a refresh" do
    Message.create!(conversation: @older_chat, sender: @other, body: "Newest in the other chat")
    visit conversations_path
    rows = all(".msg-rows .msg-row")
    assert_includes rows.first.text, @other.display_name
    assert_selector "turbo-cable-stream-source[connected]", minimum: 1, visible: false

    Message.create!(conversation: @chat, sender: @friend, body: "Are you coming tonight?")

    within(".msg-rows") do
      assert_selector ".msg-row:first-child", text: "Are you coming tonight?"
      assert_selector ".msg-row:first-child .msg-row-unread", text: "2"
      assert_selector ".msg-row", count: 2
    end
  end

  # Evergreen inbox: "the inbox comes alive". While the other person types,
  # their row in the list says "typing…" and the open chat shows the dots.
  test "typing shows in the inbox row and in the open chat" do
    visit conversations_path
    row = "##{ActionView::RecordIdentifier.dom_id(@chat, :inbox_row)}"
    assert_selector "#{row} .msg-row-preview", text: "Hello brother"

    # Keep saying "typing" until the page's subscription is live.
    seen = 20.times.any? do
      ConversationTypingChannel.broadcast_to(@chat, user_id: @friend.id, username: @friend.display_name, typing: true)
      has_selector?("#{row}.is-typing .msg-row-typing", text: "typing…", wait: 0.4)
    end
    assert seen, "the row shows typing…"
    assert_no_selector "#{row} .msg-row-preview", text: "Hello brother"

    visit conversation_path(@chat)
    seen = 20.times.any? do
      ConversationTypingChannel.broadcast_to(@chat, user_id: @friend.id, username: @friend.display_name, typing: true)
      has_selector?(".msg-thread.is-typing .typing-indicator .typing-dots", wait: 0.4)
    end
    assert seen, "the chat shows the typing dots"
    assert_selector ".msg-thread-typing", text: "typing…"
    # The composer stays on screen above everything at phone size.
    assert_selector "#new_message .msg-compose-input", visible: true
  end

  # Trello: a message that arrived while the app was in the background (live
  # connection dropped) was missing from Recent chats until a manual refresh.
  test "a chat missed while the app was in the background appears when the inbox comes back" do
    visit conversations_path
    assert_text "inbox_friend"
    newcomer = create_member("inbox_newcomer", welcomed_at: Time.current, tour_completed_at: Time.current)
    chat = Conversation.find_or_create_between!(@me, newcomer)
    # As if the broadcast never reached this phone: no live update.
    Message.skip_callback(:commit, :after, :broadcast_inbox_rows) rescue nil
    begin
      Message.create!(conversation: chat, sender: newcomer, body: "Are you coming on Sunday?")
    ensure
      Message.set_callback(:commit, :after, :broadcast_inbox_rows, on: :create) rescue nil
    end
    assert_no_text "inbox_newcomer", wait: 1

    # The app goes to the background and comes back.
    page.execute_script(<<~JS)
      Object.defineProperty(document, "hidden", { configurable: true, get: () => true })
      document.dispatchEvent(new Event("visibilitychange"))
    JS
    sleep 2.2
    page.execute_script(<<~JS)
      Object.defineProperty(document, "hidden", { configurable: true, get: () => false })
      document.dispatchEvent(new Event("visibilitychange"))
    JS
    assert_selector "#msg_rows", text: "inbox_newcomer", wait: 6
  end
end

# frozen_string_literal: true

require "test_helper"

# QA board, 26 Nov 2026 (Abbie, Android app):
#   ZCHlJfXh  reactions missing from the chat message ⋯ menu
#   s79j8vDe  download buttons on shared media too prominent
#   Y4WN7EFD  "Your walk" missing from the phone feed
class QaBoardFixesNov26Test < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActionView::RecordIdentifier

  QUICK = %w[❤️ 🙏 😂 😮 😢 👍].freeze

  setup do
    @ada = create_member("ada_qa26", welcomed_at: Time.current)
    @ben = create_member("ben_qa26", welcomed_at: Time.current)
    @chat = Conversation.find_or_create_between!(@ada, @ben)
  end

  # ── ZCHlJfXh: reactions in the ⋯ menu ──

  test "every message menu leads with the quick reactions and a button for more" do
    theirs = @chat.messages.create!(sender: @ada, body: "alright mama")
    mine = @chat.messages.create!(sender: @ben, body: "Thank you so much my brother")
    sign_in @ben

    get conversation_path(@chat)
    assert_response :success

    [ theirs, mine ].each do |message|
      scope = "##{dom_id(message)} .msg-actions[data-controller~='emoji-reactions']"
      # One compact React button leads the menu; its pill of emojis is hidden until asked for.
      assert_select "#{scope} .msg-action-row > .msg-action--react:first-child[aria-expanded='false'][data-action~='click->emoji-reactions#toggleQuick']"
      assert_select "#{scope} .msg-react-pill[hidden][data-emoji-reactions-target='quick'] .msg-react-quick", count: QUICK.size
      QUICK.each do |emoji|
        assert_select "#{scope} .msg-react-quick[data-action~='click->emoji-reactions#quick'][data-emoji-reactions-emoji-param=?]", emoji
      end
      assert_select "#{scope} .msg-react-pill .msg-react-more[data-action~='click->emoji-reactions#toggle']"
      assert_select "#{scope} .fc-reaction-picker emoji-picker"
      assert_select "#{scope} .msg-action--reply"
      assert_select "#{scope} .msg-action[aria-label='Copy text'][data-message-menu-text-param=?]", message.body
    end

    # A long press opens the menu on touch screens.
    assert_select "##{dom_id(theirs)} .msg-bubble[data-action~='touchstart->message-menu#holdStart:passive']"
    assert_select "##{dom_id(theirs)} .msg-bubble[data-action~='click->message-menu#swallowClick:capture']"
  end

  test "reacting from the menu shows the reaction under the message, and your pick is marked to take back" do
    theirs = @chat.messages.create!(sender: @ada, body: "alright mama")
    sign_in @ben

    post likes_path(likeable_type: "Message", likeable_id: theirs.id, reaction_emoji: "🙏"),
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_select "turbo-stream[action='replace'][target='#{dom_id(theirs)}']"
    assert_select ".msg-reactions .msg-reaction.is-mine", text: /🙏/
    assert_select ".msg-react-quick.is-mine[aria-pressed='true']", text: "🙏"
    assert_select ".msg-actions[data-emoji-reactions-mine-emoji-value=?]", "🙏"
    assert_select ".msg-actions[data-emoji-reactions-unlike-url-value=?]", unlike_path(likeable_type: "Message", likeable_id: theirs.id)
  end

  test "reactions under a message are grouped chips with a count only past one" do
    group_chat = @chat
    theirs = group_chat.messages.create!(sender: @ada, body: "Amen")
    theirs.likes.create!(user: @ada, reaction_type: :love, reaction_emoji: "❤️")
    theirs.likes.create!(user: @ben, reaction_type: :love, reaction_emoji: "❤️")
    sign_in @ben

    get conversation_path(@chat)
    assert_select "##{dom_id(theirs)} .msg-reactions .msg-reaction", count: 1
    assert_select "##{dom_id(theirs)} .msg-reactions .msg-reaction.is-mine .msg-reaction-count", text: "2"
  end

  test "a reaction is pushed live to the other person in the chat" do
    theirs = @chat.messages.create!(sender: @ada, body: "alright mama")
    sign_in @ben

    assert_enqueued_jobs 2, only: Turbo::Streams::ActionBroadcastJob do
      post likes_path(likeable_type: "Message", likeable_id: theirs.id, reaction_emoji: "😂"),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
  end

  # ── s79j8vDe: quieter media ──

  test "photos and voice notes have no download buttons on the bubble; tapping a photo still opens the viewer" do
    photo = @chat.messages.new(sender: @ada, body: "")
    photo.images.attach(io: StringIO.new("fake"), filename: "Sunday.png", content_type: "image/png")
    photo.save!(validate: false)
    voice = @chat.messages.new(sender: @ada, body: "")
    voice.voice_note.attach(io: StringIO.new("OggS voice"), filename: "voice-note.ogg", content_type: "audio/ogg")
    voice.save!(validate: false)
    sign_in @ben

    get conversation_path(@chat)

    assert_select ".msg-bubble .msg-media-get", count: 0
    assert_select "##{dom_id(photo)} .msg-images[data-controller='lightbox'] img.msg-image[data-download]"
    assert_select "##{dom_id(photo)} .msg-actions .msg-action--download"
    assert_select "##{dom_id(voice)} .msg-voice-player[data-controller='voice-player'] .msg-voice-play[data-action~='voice-player#toggle']"
    assert_select "##{dom_id(voice)} .msg-actions .msg-action--download[href*='/files/']"
  end

  # ── Y4WN7EFD: Your walk on phones ──

  test "the feed has a Your walk strip for phones with each stat leading somewhere" do
    @ben.user_reading_plans.create!(plan_slug: "psalms-30", current_day: 2)
    sign_in @ben

    get feed_path
    assert_response :success

    assert_select "details.eg-walkstrip#your-walk[open][data-controller='walk-strip']" do
      assert_select "summary .eg-walkstrip-title", "Your walk"
      assert_select ".eg-walkstat .eg-walkstat-label", text: "Breath streak"
      assert_select "a.eg-walkstat.is-plan[href=?]", reading_plan_path("psalms-30") do
        assert_select ".eg-walkstat-value", text: %r{Day 2/\d+}
        assert_select ".eg-walkstat-bar"
      end
      assert_select "a.eg-walkstat .eg-walkstat-label", text: "Prayed this week"
      assert_select "a.eg-walkstat.is-more[href=?]", walk_path
    end
    # The strip comes right after the Daily Bible card.
    body = response.body
    assert_operator body.index('id="daily_bible_card"'), :<, body.index('id="your-walk"')
    # The desktop rail keeps its card.
    assert_select "aside.eg-left section.eg-walk"
  end

  test "the strip leaves Bible reading to the Daily Bible card while that card is open" do
    sign_in @ben
    habit = BibleHabit.for(@ben)
    habit.update_columns(last_read_on: habit.today - 1, current_streak: 5)

    get feed_path
    assert_select "#daily_bible_card.is-open"
    assert_select "#your-walk .eg-walkstat-label", text: "Bible streak", count: 0
    assert_select "#your-walk .eg-walkstrip-peek", text: /5/

    # Folded down to one line, the strip carries the Bible streak.
    habit.update_columns(card_collapsed_on: habit.today)
    get feed_path
    assert_select "#your-walk .eg-walkstat", text: /5 days\s*Bible streak/

    # Put away until tomorrow, likewise.
    habit.update_columns(card_collapsed_on: nil, card_hidden_on: habit.today)
    get feed_path
    assert_select "#your-walk .eg-walkstat-label", text: "Bible streak", count: 1
  end

  # "week = 1.week.ago.." ran on into the next line (an endless range takes
  # the next expression as its end), so "Prayed this week" was always 0.
  test "Prayed this week counts this week's prayers" do
    room = Room.create!(name: "QA26 Prayer", description: "x", is_public: true)
    request = Post.create!(title: "Pray for my mum", content: "Surgery on Friday.", room: room, user: @ada, status: "published")
    request.likes.create!(user: @ben, reaction_type: :praying, reaction_emoji: Like.reaction_emoji(:praying))
    old = Post.create!(title: "Old one", content: "Last month.", room: room, user: @ada, status: "published")
    old.likes.create!(user: @ben, reaction_type: :praying, reaction_emoji: Like.reaction_emoji(:praying), created_at: 3.weeks.ago)
    sign_in @ben

    get feed_path
    assert_select "aside.eg-left .eg-walk-row", text: /Prayed this week\s*1/
    assert_select "#your-walk .eg-walkstat", text: /1\s*Prayed this week/

    get walk_path
    assert_select ".eg-walk-row", text: /Prayed this week\s*1/
  end

  test "Your walk has its own page, linked from your profile" do
    sign_in @ben

    get walk_path
    assert_response :success
    assert_select "section.eg-walk h2", "Your walk"

    get user_path(@ben.username)
    assert_select ".profile-actions a[href=?]", walk_path, text: /Your walk/

    sign_out @ben
    get walk_path
    assert_redirected_to new_user_session_path
  end
end

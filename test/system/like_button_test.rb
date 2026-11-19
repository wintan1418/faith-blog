# frozen_string_literal: true

require "application_system_test_case"

# A tester found the feed's Like button opened a whole emoji picker on every
# tap — too much for a simple like. Now a tap Loves the breath at once, a
# second tap takes it back, and holding the button opens the picker. The
# button always shows the heart icon (filled once you've reacted); the
# reaction you chose is on data-reaction and in the summary row.
class LikeButtonTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @member = create_member("like_tap_member", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i,
                                               tour_completed_at: Time.current, onboarding_dismissed_at: Time.current)
    author = create_member("like_tap_author")
    room = Room.create!(name: "Like Room", description: "x", room_type: :general, is_public: true)
    @post = Post.create!(user: author, room: room, title: "Rejoice always", content: "Grace and peace " * 20,
                         status: :published, moderation_status: :approved, allow_comments: true)
    login_as @member, scope: :user
  end

  teardown { Warden.test_reset! }

  test "a tap loves the breath, a second tap takes it back" do
    visit feed_path
    button = "##{reactions_id} .fc-react-btn"

    find(button).click
    assert_selector "#{button}.is-mine[data-reaction='❤️'] svg"
    assert_equal "❤️", @member.likes.find_by(likeable: @post)&.reaction_emoji
    assert_selector "##{reactions_id} .fc-reaction-picker.hidden", visible: :all

    find(button).click
    assert_no_selector "#{button}.is-mine"
    assert_nil @member.likes.find_by(likeable: @post)
  end

  test "holding the button opens the picker without reacting" do
    visit feed_path
    button = find("##{reactions_id} .fc-react-btn")
    # The hold starts on pointerdown, so the controller must be listening
    # before we press (a click works either way, a hold doesn't).
    assert page.evaluate_async_script(<<~JS, reactions_id), "the reactions controller never connected"
      const [ id, done ] = arguments
      const ready = () => window.Stimulus?.getControllerForElementAndIdentifier(document.getElementById(id), "emoji-reactions")
      const wait = (n) => ready() ? done(true) : n ? setTimeout(() => wait(n - 1), 50) : done(false)
      wait(100)
    JS

    page.driver.browser.action.click_and_hold(button.native).pause(duration: 0.7).release.perform
    assert_selector "##{reactions_id} .fc-reaction-picker:not(.hidden)"
    sleep 0.3
    assert_nil @member.likes.find_by(likeable: @post), "holding shouldn't react"

    page.execute_script(<<~JS)
      document.querySelector("##{reactions_id} emoji-picker")
        .dispatchEvent(new CustomEvent("emoji-click", { detail: { unicode: "🙏" }, bubbles: true }))
    JS
    assert_selector "##{reactions_id} .fc-react-btn.is-mine[data-reaction='🙏'] svg"
    assert_equal "🙏", @member.likes.find_by(likeable: @post)&.reaction_emoji
  end

  private

  def reactions_id = ActionView::RecordIdentifier.dom_id(@post, :reactions)
end

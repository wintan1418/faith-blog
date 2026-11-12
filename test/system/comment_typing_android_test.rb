# frozen_string_literal: true

require "application_system_test_case"

# Android keyboards (Gboard, Samsung) type through composition/beforeinput
# events, often with no usable keydown. The comment box's autofill guard
# (pristine-field) only counted keydown as typing, so it kept wiping what
# Android users wrote. These tests put text in the box the way an Android
# keyboard does, with no keydown, and check it survives the guard's window.
class CommentTypingAndroidTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @member = create_member("comment_typist", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i,
                                              tour_completed_at: Time.current, onboarding_dismissed_at: Time.current)
    author = create_member("comment_author")
    room = Room.create!(name: "Typing Room", description: "x", room_type: :general, is_public: true)
    @post = Post.create!(user: author, room: room, title: "Pray with me", content: "Grace and peace",
                         status: :published, moderation_status: :approved)
    login_as @member, scope: :user
  end

  teardown { Warden.test_reset! }

  def type_like_android(script)
    visit post_path(@post)
    find("#comment_form .composer-collapsed").click
    find("#comment_form trix-editor", visible: true)
    page.execute_script(<<~JS)
      const editor = document.querySelector("#comment_form trix-editor")
      editor.focus()
      #{script}
    JS
    sleep 2.3 # past the guard's last re-check (1.8s after load, 250ms after focus)
    page.evaluate_script(%(document.querySelector("#comment_form trix-editor").editor.getDocument().toString().trim()))
  end

  test "text inserted with no keydown (composition) stays in the comment box" do
    text = type_like_android(<<~JS)
      editor.dispatchEvent(new CompositionEvent("compositionstart", { bubbles: true }))
      editor.editor.insertString("Amen brother")
    JS
    assert_equal "Amen brother", text
  end

  test "text that only arrives as a change while focused stays in the comment box" do
    text = type_like_android(%(editor.editor.insertString("Praying for you")))
    assert_equal "Praying for you", text
  end
end

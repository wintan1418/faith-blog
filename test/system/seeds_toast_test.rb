# frozen_string_literal: true

require "application_system_test_case"

# Seeds in the browser: a comment shows "+5 seeds", and crossing a rank opens
# the celebration once.
class SeedsToastTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @member = create_member("seed_typist", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i,
                                           tour_completed_at: Time.current, onboarding_dismissed_at: Time.current)
    author = create_member("seed_post_author")
    room = Room.create!(name: "Seed Room", description: "x", room_type: :general, is_public: true)
    @post = Post.create!(user: author, room: room, title: "Pray with me", content: "Grace and peace",
                         status: :published, moderation_status: :approved)
    login_as @member, scope: :user
  end

  teardown { Warden.test_reset! }

  def comment!(text)
    visit post_path(@post)
    find("#comment_form .composer-collapsed").click
    find("#comment_form trix-editor", visible: true)
    sleep 2 # past the autofill guard's window
    page.execute_script(<<~JS)
      const editor = document.querySelector("#comment_form trix-editor")
      editor.focus()
      editor.editor.insertString(#{text.to_json})
    JS
    within("#comment_form") { click_on "Post" }
  end

  test "commenting shows the +5 seeds toast, and a rank-up opens the celebration once" do
    SeedEvent.create!(user: @member, kind: "badge", points: 46, source: @post, created_on: Date.current, created_at: Time.current)
    Seeds.recompute_totals!(@member.id)

    comment!("What a faithful word, thank you for sharing")

    assert_selector ".seed-toast", text: "+5 seeds", wait: 5
    assert_selector "dialog.seed-rankup[open]", text: "You're now a Sprout", wait: 5
    click_on "Keep going"
    assert_no_selector "dialog.seed-rankup[open]", wait: 3

    assert_equal 1, @member.reload.seeds_rank_seen
    visit post_path(@post)
    assert_no_selector "dialog.seed-rankup", visible: :all
  end
end

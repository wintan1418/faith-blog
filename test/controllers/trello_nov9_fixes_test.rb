# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Fixes for the testers' cards of 9 November 2026.
class TrelloNov9FixesTest < ActionDispatch::IntegrationTest
  APP_UA = "Brethreign/1.0.8; Hotwire Native Android; Turbo Native Android"
  CARD = { church_or_assembly: "Grace Assembly", occupation: "Nurse", whatsapp_number: "+2348000000000",
           email: "card@example.com", bio: "Serving in the choir." }.freeze

  setup do
    @me = create_member("nov9_me")
    sign_in @me
  end

  test "saving the Brethren Card goes back to the profile on the web" do
    patch settings_brethren_card_path, params: { brethren_card: CARD }
    assert_redirected_to user_path(@me.username)
    assert @me.reload.brethren_card.complete?
  end

  test "saving the Brethren Card closes the edit screen in the app" do
    patch settings_brethren_card_path, params: { brethren_card: CARD }, headers: { "User-Agent" => APP_UA }
    assert_match %r{/recede_historical_location}, response.location
  end

  test "a draft can be scheduled from the draft editor" do
    draft = @me.posts.create!(title: "Later", content: "A breath for tomorrow morning.", status: :draft, moderation_status: :approved)
    get edit_post_path(draft)
    assert_select "[data-controller=schedule-field] input[type=datetime-local]"

    at = 2.days.from_now.change(sec: 0)
    patch post_path(draft), params: { post: { status: "published", scheduled_for: at.utc.iso8601 } }
    draft.reload
    assert draft.scheduled?
    assert_nil draft.published_at
    assert_in_delta at.to_i, draft.scheduled_for.to_i, 1
    assert_redirected_to drafts_path
  end

  test "publishing a scheduled breath with no time sends it now" do
    post = @me.posts.create!(title: "Soon", content: "Was scheduled, going now.", status: :scheduled,
                             scheduled_for: 1.day.from_now, moderation_status: :approved)
    patch post_path(post), params: { post: { status: "published", scheduled_for: "" } }
    post.reload
    assert post.published?
    assert_nil post.scheduled_for
    assert post.published_at.present?
  end

  test "See all opens suggestions with Connect, and the people list offers Connect too" do
    church = create_member("nov9_church")
    @me.profile.update!(assembly: "Grace Assembly, Lekki")
    church.profile.update!(assembly: "Grace Assembly, Lekki")

    get suggested_people_path
    assert_response :success
    assert_select ".bys-grid .bys-card", minimum: 1
    assert_select "#suggestion_user_#{church.id}"

    get people_path
    assert_select "a.bys-all[href=?]", suggested_people_path
    assert_select "#connection_actions_user_#{church.id}", text: /Connect/
  end

  test "the ladder asks Lichess for the chosen difficulty only" do
    asked = []
    fake = ->(difficulty = nil) { asked << difficulty; { id: "x", rating: 1200, solution: %w[e2e4], fen: "8/8/8/8/8/8/8/8 w - - 0 1" } }
    Lichess::DailyPuzzle.stub(:practice, fake) do
      get games_chess_practice_path(difficulty: "hardest"), as: :json
    end
    assert_response :success
    assert_equal [ "hardest" ], asked
  end
end

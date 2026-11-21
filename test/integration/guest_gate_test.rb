# frozen_string_literal: true

require "test_helper"

# "Join to continue": signed-out web visitors can read the page they land on,
# but clicking further opens a join / sign-in dialog (guest_gate_controller.js).
# The apps and signed-in members never get it, and the server still requires
# sign-in for every action that did before.
class GuestGateTest < ActionDispatch::IntegrationTest
  APP_UA = "Brethreign/1.0.8; Hotwire Native Android; Turbo Native Android"

  setup do
    @member = create_member("gate_member")
    @room = Room.create!(name: "Gate Room", description: "x", is_public: true)
    @post = Post.create!(title: "Morning grace", content: "Grace.", room: @room, user: @member, status: "published")
  end

  test "signed-out web visitors get the gate on the body, with the dialog" do
    get root_path(browse: 1)

    assert_select "body[data-controller~='guest-gate']"
    assert_select "dialog.guest-gate[data-guest-gate-target='dialog'][data-guest-gate-allow]" do
      assert_select "h2", text: "Join Brethreign to keep reading"
      assert_select "a[href=?]", new_user_registration_path, text: "Create account"
      assert_select "a[href=?]", new_user_session_path, text: "Sign in"
      assert_select "button[aria-label='Close'][data-action='guest-gate#close']"
    end
    # The public feed stops after the first page with a join card.
    assert_select ".guest-more", text: /Join to see more/
  end

  test "a shared link still renders in full for a signed-out visitor, with the gate" do
    get post_path(@post)

    assert_response :success
    assert_select "meta[property='og:title']"
    assert_select "body[data-controller~='guest-gate']"
    assert_select "dialog.guest-gate"
  end

  test "the parts that must keep working are marked open" do
    get root_path
    assert_select "a.welcome-browse[data-guest-gate-allow]", text: "Look around first"
    assert_select "[data-guest-gate-allow] form[action=?]", waitlist_path

    get root_path(browse: 1)
    assert_select "#flash_messages[data-guest-gate-allow]"
    assert_select "button[data-controller='theme'][data-guest-gate-allow]"
  end

  test "signed-in members never get the gate" do
    sign_in @member
    get post_path(@post)

    assert_select "body[data-controller~='guest-gate']", false
    assert_select "dialog.guest-gate", false
  end

  test "the apps never get the gate" do
    get root_path, headers: { "User-Agent" => APP_UA }

    assert_select "body[data-controller~='guest-gate']", false
    assert_select "dialog.guest-gate", false
    assert_select ".guest-more", false
    assert_select ".home-feed-card", minimum: 1
  end

  test "actions that need an account still send guests to sign in" do
    post likes_path(likeable_type: "Post", likeable_id: @post.id)
    assert_redirected_to new_user_session_path

    post post_comments_path(@post), params: { comment: { content: "Amen" } }
    assert_redirected_to new_user_session_path

    post post_bookmark_path(@post)
    assert_redirected_to new_user_session_path

    get feed_path
    assert_redirected_to new_user_session_path

    get feed_path(page: 2)
    assert_redirected_to new_user_session_path
  end
end

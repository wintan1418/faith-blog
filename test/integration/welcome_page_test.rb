# frozen_string_literal: true

require "test_helper"

# "/" for signed-out web visitors is a welcome page (brand, Join, Sign in);
# the public feed is one tap away, and the apps keep their old flow.
class WelcomePageTest < ActionDispatch::IntegrationTest
  APP_UA = "Brethreign/1.0.8; Hotwire Native Android; Turbo Native Android"

  setup do
    @member = create_member("welcome_member")
    room = Room.create!(name: "Welcome Room", description: "x", is_public: true)
    @post = Post.create!(title: "Morning grace", content: "Grace.", room: room, user: @member, status: "published")
  end

  test "signed-out web visitors get the welcome page, not the feed" do
    get root_path

    assert_response :success
    assert_select "h1", text: "Faith at the centre. Everyone welcome."
    assert_select ".welcome-sub", text: "Sane, kind conversations about everything."
    assert_select "a[href=?]", new_user_registration_path, text: "Create account"
    assert_select "a[href=?]", new_user_session_path, text: "Sign in"
    assert_select "a[href=?]", root_path(browse: 1), text: "Look around first"
    assert_select ".welcome-footer a[href=?]", about_path
    assert_select ".welcome-footer a[href=?]", privacy_path
    assert_select ".welcome-footer a[href=?]", terms_path
    assert_select ".welcome-footer a[href=?]", child_safety_path
    assert_select ".home-feed-card", false
    assert_select "nav.fc-topbar", false
    # Link previews still work on "/".
    assert_select "meta[property='og:title'][content*=?]", "Brethreign"
    assert_select "meta[property='og:description'][content*=?]", "Faith at the centre"
    assert_select "meta[property='og:image']"
  end

  test "the welcome page reuses the Google button when Google sign-in is set up" do
    with_env("GOOGLE_CLIENT_ID" => "id", "GOOGLE_CLIENT_SECRET" => "secret") do
      get root_path
      assert_select ".welcome .google-auth-button", text: /Continue with Google/
      assert_select ".welcome .auth-divider", text: "or"
    end
  end

  test "Look around first shows the public feed" do
    get root_path(browse: 1)

    assert_response :success
    assert_select ".welcome", false
    assert_select ".home-feed-card", minimum: 1
    assert_select "a[href=?]", post_path(@post)
    # The guest Feed links keep the visitor in the feed, not back at the welcome page.
    assert_select ".eg-pills a[href=?]", root_path(browse: 1)
  end

  test "signed-in members still go straight to their feed" do
    sign_in @member
    get root_path
    assert_redirected_to feed_path
  end

  test "the apps keep opening / straight into the public feed" do
    get root_path, headers: { "User-Agent" => APP_UA }

    assert_response :success
    assert_select ".welcome", false
    assert_select ".home-feed-card", minimum: 1
  end

  test "shared links stay public" do
    get post_path(@post)
    assert_response :success
    [ privacy_path, terms_path, child_safety_path, about_path ].each do |path|
      get path
      assert_response :success, path
    end
  end

  private

  def with_env(vars)
    old = vars.keys.index_with { |k| ENV[k] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end

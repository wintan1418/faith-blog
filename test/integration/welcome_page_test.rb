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

  test "the welcome page tells the new dawn story" do
    get root_path

    assert_select ".welcome-brand figure.dawn-wrap" do
      assert_select ".dawn[role=img][aria-label=?]",
                    "The old Brethreign logo sets like the moon as the new logo rises like the sun. New look coming soon."
      assert_select ".dawn-moon svg path" # the current mark, as the moon
      assert_select ".dawn-sun svg.dawn-mark path", count: 3 # the new B: two rings and the B
      assert_select ".dawn-sun svg.dawn-mark path[fill-opacity='.2']"
      assert_select ".dawn-sun svg.dawn-mark path[fill-opacity='.6']"
      assert_select "figcaption .dawn-eyebrow", text: "Unveiling soon"
      assert_select "figcaption", text: /A new dawn for Brethreign\. Our new look is almost here\./
    end
    assert_select ".welcome-word", text: "Brethreign"
  end

  test "the welcome page has Get the app: coming-soon badges and the waitlist form" do
    get root_path

    assert_select "section#get-the-app[data-guest-gate-allow]" do
      assert_select "h2", text: "Get the app"
      assert_select ".app-badge", count: 2
      assert_select ".app-badge", text: /App Store/
      assert_select ".app-badge", text: /Google Play/
      assert_select ".app-badge .app-badge-soon", text: "Coming soon", count: 2
      assert_select ".app-badge a", false # not links yet
      assert_select "form[action=?][method=post]", waitlist_path do
        assert_select "label[for=waitlist_email]"
        assert_select "input#waitlist_email[type=email][autocomplete=email]"
        assert_select "fieldset legend"
        assert_select "input[type=radio][name='app_waitlist_entry[platform]']", count: 3
        assert_select "input#waitlist_platform_both[checked]"
        assert_select "input[name=?][value='']", SignupGuard::HONEYPOT_PARAM.to_s
        assert_select "input[type=hidden][name=?]", SignupGuard::TOKEN_PARAM.to_s
        assert_select "button[type=submit]", text: "Notify me"
      end
      assert_select ".waitlist-note", text: "We'll only email you when the app is ready. No spam."
    end
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

  test "a request for JSON at / still gets the welcome page instead of a crash" do
    get root_path, headers: { "Accept" => "application/json" }
    assert_response :success
    assert_equal "text/html", response.media_type
  end

  test "the guest feed mixes authors instead of one long run" do
    mk = ->(n) { User.create!(username: "mix#{n}", email: "mix#{n}@example.com", password: SecureRandom.base58(16)) }
    busy = mk.call(1)
    others = [ mk.call(2), mk.call(3), mk.call(4) ]
    6.times { |i| Post.create!(user: busy, title: "Busy #{i}", content: "Busy post #{i}", status: :published, published_at: i.minutes.ago) }
    others.each_with_index { |u, i| 2.times { |j| Post.create!(user: u, title: "Other #{i}#{j}", content: "Other post #{i}#{j}", status: :published, published_at: (10 + i * 2 + j).minutes.ago) } }
    get root_path(browse: 1)
    assert_response :success
    stream = Nokogiri::HTML(response.body).at_css("section.home-feed-stream")
    order = stream.css("article.home-feed-card .home-author-copy strong").map { |n| n.text.strip }
    assert order.size >= 6, "expected the feed cards, got #{order.inspect}"
    runs = order.chunk_while { |a, b| a == b }.map(&:size)
    assert runs.max <= 2, "longest run was #{runs.max}: #{order.inspect}"
  end
end

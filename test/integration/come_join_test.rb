# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# "Come join the conversation": personal invite links (/join/username), who
# gets credit for a sign-up, and the inviter's seeds once the friend is real.
class ComeJoinTest < ActionDispatch::IntegrationTest
  LONG = "So glad to be here, thank you for bringing me into this conversation"

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    seen = { welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i,
             tour_completed_at: Time.current, onboarding_dismissed_at: Time.current }
    @ada = create_member("ada_invites", **seen)
    @room = Room.create!(name: "Work & Life", description: "x", is_public: true)
  end

  def sign_up(username)
    post user_registration_path, params: { user: { username: username, email: "#{username}@example.com",
                                                   password: SecureRandom.base58(16) } }.merge(human_signup_fields)
    User.find_by!(username: username)
  end

  def publish(user, title: "Hello")
    Post.create!(user: user, room: @room, title: title, content: "Glad to be here, a first breath",
                 status: :published, moderation_status: :approved, published_at: Time.current)
  end

  def invite_seeds(user) = SeedEvent.where(user: user, kind: "invite_joined")

  # ── Landing page ──

  test "the landing page shows the inviter and absolute OG tags" do
    other = create_member("talker")
    Post.create!(user: other, room: @room, title: "Work and rest", content: "How do you all switch off after a long week at work?",
                 status: :published, moderation_status: :approved, published_at: 1.hour.ago, likes_count: 4)
    Post.create!(user: other, room: @room, title: "Anon", content: "A secret thought that nobody should be able to see here",
                 status: :published, moderation_status: :approved, published_at: 1.hour.ago, anonymous: true, likes_count: 50)

    get join_invite_path("ADA_invites")

    assert_response :success
    assert_select "h1", text: "ada_invites invited you"
    assert_select %(meta[property="og:title"][content="ada_invites invited you to Brethreign"])
    assert_select %(meta[name="twitter:title"][content="ada_invites invited you to Brethreign"])
    assert_select %(meta[property="og:image"][content="http://www.example.com/og/invite.jpg"])
    assert_select %(meta[name="twitter:image"][content="http://www.example.com/og/invite.jpg"])
    assert_select %(meta[property="og:url"][content="http://www.example.com/join/ada_invites"])
    assert_select ".cj-snippet", text: /switch off after a long week/
    assert_not_includes response.body, "A secret thought"
    assert_not_includes response.body, @ada.email
    assert_select %(a.cj-join[href="#{new_user_registration_path}"])
    assert cookies[InviteAttribution::COOKIE.to_s].present?
  end

  test "prayer requests, private rooms and minors' breaths stay off the landing page" do
    hidden_room = Room.create!(name: "Private", description: "x", is_public: false)
    kid = create_member("young_one")
    kid.profile.update!(birth_year: Date.current.year - 15)
    Post.create!(user: create_member("prayer_person"), room: @room, title: "Please pray", content: "Please pray for my family this week, we need it",
                 status: :published, moderation_status: :approved, published_at: 1.hour.ago, prayer_status: :prayer_pending)
    Post.create!(user: create_member("insider"), room: hidden_room, title: "Inside", content: "Something said inside a private room only for members",
                 status: :published, moderation_status: :approved, published_at: 1.hour.ago)
    Post.create!(user: kid, room: @room, title: "School", content: "What subjects did everyone enjoy at school growing up?",
                 status: :published, moderation_status: :approved, published_at: 1.hour.ago)

    get join_invite_path(@ada.username)
    assert_response :success
    assert_select ".cj-snippet", 0
    assert_select ".cj-empty"
  end

  test "deactivated, under-18 and unknown inviters get the generic page and no attribution" do
    gone = create_member("gone_member", active: false)
    minor = create_member("minor_member")
    minor.profile.update!(birth_year: Date.current.year - 16)

    [ gone.username, minor.username, "nobody_here" ].each do |name|
      get join_invite_path(name)
      assert_response :success
      assert_select "h1", text: "Come join the conversation"
      assert_select %(meta[property="og:title"][content="Come join the conversation on Brethreign"])
      assert_not_includes response.body, "#{name} invited you"
      assert cookies[InviteAttribution::COOKIE.to_s].blank?, "no cookie for #{name}"
    end
  end

  test "signed-in members who open a link go to the feed" do
    sign_in create_member("already_here")
    get join_invite_path(@ada.username)
    assert_redirected_to feed_path
  end

  test "the inviter opening their own link goes to the feed without attribution" do
    sign_in @ada
    get join_invite_path(@ada.username)
    assert_redirected_to feed_path
    assert cookies[InviteAttribution::COOKIE.to_s].blank?
  end

  test "the landing page is rate limited per IP" do
    JoinsController::PAGE_LIMIT.times { get join_invite_path(@ada.username) }
    assert_response :success
    get join_invite_path(@ada.username)
    assert_response :too_many_requests
  end

  test "a broken cache never breaks the landing page" do
    broken = Object.new
    def broken.increment(*) = raise("cache down")
    RateLimitStore.stub(:store, broken) do
      get join_invite_path(@ada.username)
    end
    assert_response :success
  end

  # ── Attribution ──

  test "signing up through the link credits the inviter" do
    get join_invite_path(@ada.username)
    get new_user_registration_path
    assert_select ".auth-invited-by", text: /ada_invites invited you/

    friend = sign_up("friend_one")
    assert_equal @ada, friend.invited_by
    assert_equal [ friend ], @ada.invitees.to_a
    assert cookies[InviteAttribution::COOKIE.to_s].blank?, "the cookie is used once"
  end

  test "signing up without the link credits nobody" do
    friend = sign_up("loner")
    assert_nil friend.invited_by_id
  end

  test "an accepted email invitation wins over the link" do
    emailer = create_member("email_inviter")
    Invitation.create!(inviter: emailer, email: "both_ways@example.com")

    get join_invite_path(@ada.username)
    friend = sign_up("both_ways")
    assert_equal emailer, friend.reload.invited_by
  end

  test "Google sign-up on the web through the link credits the inviter; an existing account is not" do
    get join_invite_path(@ada.username)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "g-come-join", info: { email: "googler@example.com", name: "Googler" }
    )
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:google_oauth2]
    get user_google_oauth2_omniauth_callback_path

    googler = User.find_by!(email: "googler@example.com")
    assert_equal @ada, googler.invited_by

    old = create_member("old_member", created_at: 2.days.ago)
    sign_out googler
    get join_invite_path(@ada.username)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2", uid: "g-old", info: { email: old.email, name: "Old" }
    )
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:google_oauth2]
    get user_google_oauth2_omniauth_callback_path
    assert_nil old.reload.invited_by_id
  ensure
    OmniAuth.config.test_mode = false
    Rails.application.env_config.delete("omniauth.auth")
  end

  test "Google sign-up in the apps through the link credits the inviter" do
    previous = ENV["GOOGLE_CLIENT_ID"]
    ENV["GOOGLE_CLIENT_ID"] = "web-client.apps.googleusercontent.com"
    app = { "User-Agent" => "Brethreign NativeGoogleSignIn; Hotwire Native Android; Turbo Native Android" }
    get join_invite_path(@ada.username), headers: app
    payload = { "sub" => "g-app-join", "email" => "appjoin@example.com", "email_verified" => true, "name" => "App Join" }
    Google::Auth::IDTokens.stub(:verify_oidc, ->(*, **) { payload }) do
      post native_google_sign_in_path, params: { id_token: "t" }, as: :json, headers: app
    end
    assert_response :success
    assert_equal @ada, User.find_by!(email: "appjoin@example.com").invited_by
  ensure
    ENV["GOOGLE_CLIENT_ID"] = previous
  end

  test "you can never be your own inviter" do
    assert_nil InviteAttribution.apply!(@ada, Struct.new(:signed) { def delete(*) = nil }.new({ InviteAttribution::COOKIE => @ada.id }))
    assert_nil @ada.reload.invited_by_id
  end

  # ── Seeds ──

  test "the inviter earns seeds only once the friend posts, and only once" do
    friend = create_member("new_friend", invited_by: @ada)
    assert_equal 0, @ada.reload.seeds_total

    publish(friend)
    assert_equal 1, invite_seeds(@ada).count
    assert_equal Seeds.points_for("invite_joined"), invite_seeds(@ada).first.points
    assert_equal friend.id, invite_seeds(@ada).first.actor_id

    publish(friend, title: "Again")
    assert_equal 1, invite_seeds(@ada).count, "paid once per friend"
  end

  test "a first approved comment with real words also counts; a one-word one doesn't" do
    friend = create_member("commenter_friend", invited_by: @ada)
    breath = publish(create_member("someone_else"))

    Comment.create!(post: breath, user: friend, content: "Amen")
    assert_equal 0, invite_seeds(@ada).count

    Comment.create!(post: breath, user: friend, content: LONG)
    assert_equal 1, invite_seeds(@ada).count
  end

  test "a held breath pays nothing until it goes live" do
    friend = create_member("held_friend", invited_by: @ada)
    Post.create!(user: friend, room: @room, title: "Held", content: "Waiting for review",
                 status: :published, moderation_status: :pending_review, published_at: Time.current)
    assert_equal 0, invite_seeds(@ada).count
  end

  test "invite seeds are capped per day" do
    cap = Seeds::RULES["invite_joined"][:daily_cap]
    (cap + 1).times do |i|
      publish(create_member("capped_#{i}", invited_by: @ada))
    end
    assert_equal cap, invite_seeds(@ada).count
  end

  test "a deactivated friend or inviter earns nothing" do
    friend = create_member("inactive_friend", invited_by: @ada, active: false)
    publish(friend)
    assert_equal 0, invite_seeds(@ada).count

    @ada.update_column(:active, false)
    publish(create_member("active_friend", invited_by: @ada))
    assert_equal 0, invite_seeds(@ada).count
  end

  # ── Invite friends page ──

  test "the invite page shows the link, share buttons, the reward and who joined" do
    friend = create_member("joined_friend", invited_by: @ada)
    publish(friend)
    create_member("quiet_friend", invited_by: @ada)
    sign_in @ada

    get invite_friends_path
    assert_response :success
    url = "http://www.example.com/join/ada_invites"
    assert_select %(input.fc-invite-link-input[value="#{url}"])
    assert_select ".cj-reward", text: /\+25 seeds when a friend joins and posts/
    assert_select "textarea.cj-message-text", text: /Come join the conversation on Brethreign .* Here's my invite: #{Regexp.escape(url)}/
    %w[wa.me twitter.com/intent linkedin.com/sharing facebook.com/sharer mailto:].each do |target|
      assert_select %(a.cj-share-btn[href*="#{target}"]), 1
    end
    assert_select ".cj-joined-count", text: "2"
    assert_select ".cj-joined-item", 2
    assert_select ".cj-joined-item", text: /joined_friend.*\+25/m
    assert_select ".cj-joined-item", text: /quiet_friend.*Not posted yet/m
  end

  test "Invite friends is in the account menu, the feed and the profile" do
    @ada.update_column(:created_at, 5.days.ago)
    publish(create_member("feed_writer"))
    sign_in @ada
    get feed_path
    assert_select %(.eg-menu-item[href="#{invite_friends_path}"])
    assert_select %(.eg-more a[href="#{invite_friends_path}"])
    assert_select ".cj-feed-card", text: /Bring someone into the conversation/

    @ada.dismiss_card!(FeedController::INVITE_CARD_KEY)
    get feed_path
    assert_select ".cj-feed-card", 0

    get user_path(@ada.username)
    assert_select %(.profile-actions a[href="#{invite_friends_path}"])
  end

  test "the seeds guide lists the invite reward" do
    get seeds_guide_path
    assert_select ".seed-rule", text: /A friend joins through your invite and posts/
  end
end

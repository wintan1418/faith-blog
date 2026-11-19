# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Privacy and account-safety fixes from the Nov 2026 security audit.
class SecurityPrivacyTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @pass = "Strong-#{SecureRandom.hex(6)}"
    @author = User.create!(username: "sec_author", email: "sec-author@example.com", password: @pass)
    @reader = User.create!(username: "sec_reader", email: "sec-reader@example.com", password: @pass)
    @room = Room.create!(name: "Security Room", description: "x")
  end

  def breath(user: @author, **attrs)
    @breath_count = @breath_count.to_i + 1 # plain words only: random hex can trip the language filter
    Post.create!({ user: user, room: @room, content: "A quiet breath number #{@breath_count}", status: :published }.merge(attrs))
  end

  # ── 1. Drafts / scheduled breaths ──

  test "a draft or scheduled breath 404s for signed-out visitors and other members" do
    draft = breath(status: :draft, title: "Secret draft words")
    scheduled = breath(status: :scheduled, scheduled_for: 2.days.from_now)

    [ draft, scheduled ].each do |post|
      get post_path(post)
      assert_response :not_found, "signed out should 404 for #{post.status}"
    end

    sign_in_and_settle @reader
    [ draft, scheduled ].each do |post|
      get post_path(post)
      assert_response :not_found
      get reactions_post_path(post)
      assert_response :not_found
      post comments_path_for(post), params: { comment: { content: "hi" } }
      assert_response :not_found
      post join_prayer_chain_post_path(post)
      assert_response :not_found
      post likes_path(likeable_type: "Post", likeable_id: post.id)
      assert_redirected_to root_path # "Invalid content." — no reaction is stored
      post reports_path, params: { reportable_type: "Post", reportable_id: post.id }
      assert_response :not_found
    end
    assert_equal 0, draft.comments.count
    assert_equal 0, draft.likes.count
  end

  test "the author and admins can still open a draft" do
    draft = breath(status: :draft)
    sign_in @author
    get post_path(draft)
    assert_response :success

    admin = User.create!(username: "sec_admin1", email: "sec-admin1@example.com", password: @pass, role: :admin)
    sign_in admin
    get post_path(draft)
    assert_response :success
  end

  test "link-preview tags never carry a held breath's words" do
    held = breath(title: "Hidden held words")
    held.update_columns(moderation_status: Post.moderation_statuses[:pending_review])
    sign_in @reader
    get post_path(held)
    assert_response :success
    assert_select "meta[property='og:title'][content*='Hidden held words']", count: 0
    assert_no_match(/Hidden held words/, response.body)
  end

  # ── 2. Anonymous breaths ──

  test "anonymous breaths stay off the author's profile, rail and counts for others" do
    named = breath(title: "Named breath here")
    anon  = breath(title: "Anonymous confession", anonymous: true)

    get user_path(@author.username)
    assert_response :success
    assert_no_match(/Anonymous confession/, response.body)
    assert_select "[data-profile-hero-target='count'][data-count='1']"

    get posts_user_path(@author.username)
    assert_no_match(/Anonymous confession/, response.body)

    get post_path(named)
    assert_no_match(/Anonymous confession/, response.body)

    sign_in @author
    get user_path(@author.username)
    assert_match(/Anonymous confession/, response.body)
    assert anon.persisted?
  end

  test "followers are not notified of an anonymous breath, but are of a named one" do
    @reader.follow(@author)
    anon = breath(anonymous: true)
    BreathFanoutJob.perform_now(anon.id)
    assert_equal 0, Notification.where(user: @reader, notification_type: :breath_from_followee).count

    named = breath
    BreathFanoutJob.perform_now(named.id)
    assert_equal 1, Notification.where(user: @reader, notification_type: :breath_from_followee).count
  end

  test "notifications about an anonymous breath never name its author" do
    anon = breath(anonymous: true, content: "Please pray @#{@reader.username}")
    anon.process_mentions!(@author)
    mention = Notification.find_by(user: @reader, notification_type: :mentioned)
    assert mention
    assert_nil mention.actor_id
    assert_match(/\ASomeone/, mention.message_text(emoji: false))

    # @everyone (bulk insert path)
    @room.room_memberships.create!(user: @reader)
    shout = breath(anonymous: true, content: "Hello @everyone")
    shout.fanout_everyone_mention!(@author)
    everyone = Notification.find_by(user: @reader, notification_type: :everyone_mention, notifiable: shout)
    assert everyone
    assert_nil everyone.actor_id

    # Prayer answered → intercessors
    prayer = breath(anonymous: true, prayer_status: :prayer_pending)
    PrayerIntercession.create!(user: @reader, post: prayer)
    sign_in @author
    post mark_prayer_answered_post_path(prayer)
    answered = Notification.find_by(user: @reader, notification_type: :prayer_answered)
    assert answered
    assert_nil answered.actor_id

    sign_in @reader
    get notifications_path
    assert_response :success
    assert_no_match(/#{@author.username}/, response.body)
  end

  test "a named commenter on an anonymous breath is still shown (only the hidden author is masked)" do
    anon = breath(anonymous: true)
    note = Notification.create!(user: @author, actor: @reader, notifiable: anon, notification_type: :prayer_joined)
    assert_equal @reader.id, note.actor_id
  end

  # ── 3. Current password ──

  test "changing email or password needs the current password" do
    sign_in @author
    patch settings_account_path, params: { user: { email: "stolen@example.com" } }
    assert_response :unprocessable_entity
    assert_equal "sec-author@example.com", @author.reload.email

    patch settings_account_path, params: { user: { password: "NewPassword-123", password_confirmation: "NewPassword-123" } }
    assert_response :unprocessable_entity
    assert @author.reload.valid_password?(@pass)

    assert_emails 1 do # the OLD address hears about the change
      patch settings_account_path, params: { user: { email: "moved@example.com", current_password: @pass } }
    end
    assert_equal "moved@example.com", @author.reload.email
    assert_equal [ "sec-author@example.com" ], ActionMailer::Base.deliveries.last.to

    patch settings_account_path, params: { user: { username: "sec_author_2" } }
    assert_equal "sec_author_2", @author.reload.username
  end

  test "a Google-only account can change email only soon after signing in" do
    google = User.from_google(OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "g-1",
                                                     info: { email: "gonly@example.com", name: "G Only" }))
    assert_nil google.password_chosen_at
    sign_in_and_settle google # (the test sign-in itself stamps current_sign_in_at)
    google.update_columns(current_sign_in_at: 2.hours.ago)
    patch settings_account_path, params: { user: { email: "gonly2@example.com" } }
    assert_response :unprocessable_entity
    assert_equal "gonly@example.com", google.reload.email

    google.update_columns(current_sign_in_at: 1.minute.ago)
    patch settings_account_path, params: { user: { email: "gonly2@example.com" } }
    assert_equal "gonly2@example.com", google.reload.email
  end

  # ── 4. Brute force ──

  test "an account locks after 10 wrong passwords" do
    10.times do |i|
      AuthThrottleStore.clear! if i == 5 # isolate lockable from the rate limit
      post user_session_path, params: { user: { email: @author.email, password: "wrong-#{i}" } }
    end
    assert @author.reload.access_locked?

    AuthThrottleStore.clear!
    post user_session_path, params: { user: { email: @author.email, password: @pass } }
    assert_not_equal feed_path, URI(response.location.to_s).path if response.redirect?
    get feed_path
    assert_redirected_to new_user_session_path
  end

  test "sign-in attempts are rate limited per IP" do
    10.times { |i| post user_session_path, params: { user: { email: "nobody#{i}@example.com", password: "x" } } }
    post user_session_path, params: { user: { email: "nobody-last@example.com", password: "x" } }
    assert_response :too_many_requests
  end

  test "password resets are rate limited per email and don't reveal whether the account exists" do
    post user_password_path, params: { user: { email: "no-such-person@example.com" } }
    unknown_location = response.location
    post user_password_path, params: { user: { email: @author.email } }
    assert_equal unknown_location, response.location

    3.times { post user_password_path, params: { user: { email: @author.email } } }
    assert_response :too_many_requests
  end

  # ── 5. Bot sign-ups ──

  def signup_params(username: "fresh_soul", email: "fresh-soul@example.com", **extra)
    { user: { username: username, email: email, password: "Grace-and-peace-1" } }.merge(extra)
  end

  test "a person who takes a moment to fill the form can join" do
    assert_difference -> { User.count }, 1 do
      post user_registration_path, params: signup_params.merge(human_signup_fields)
    end
  end

  test "honeypot, instant posts and missing form stamps are rejected" do
    assert_no_difference -> { User.count } do
      post user_registration_path, params: signup_params.merge(human_signup_fields).merge(SignupGuard::HONEYPOT_PARAM => "http://spam.example")
      assert_response :unprocessable_entity
      post user_registration_path, params: signup_params.merge(human_signup_fields(shown_at: 1.second.ago))
      assert_response :unprocessable_entity
      post user_registration_path, params: signup_params
      assert_response :unprocessable_entity
    end
  end

  test "the honeypot is hidden from people and screen readers" do
    get new_user_registration_path
    assert_select "div[aria-hidden='true'] input[name='#{SignupGuard::HONEYPOT_PARAM}'][tabindex='-1']"
    assert_select "input[type='hidden'][name='#{SignupGuard::TOKEN_PARAM}']"
  end

  test "disposable email domains can't sign up" do
    assert_no_difference -> { User.count } do
      post user_registration_path, params: signup_params(email: "bot@mailinator.com").merge(human_signup_fields)
    end
    assert_match(/throwaway/, response.body)
  end

  test "repeated bot blocks raise an admin alert" do
    calls = []
    ErrorAlert.stub(:notify, ->(**kw) { calls << kw }) do
      (SignupGuard::ALERT_THRESHOLD + 1).times do
        SignupGuard.record_block!("honeypot", where: "sign-up", remote_ip: "1.2.3.4", email: "x@example.com")
      end
    end
    assert_equal 1, calls.size
    assert_match(/Bot sign-ups/, calls.first[:title])
  end

  test "Turnstile is verified server-side when its keys are set" do
    env = { "TURNSTILE_SITE_KEY" => "site", "TURNSTILE_SECRET_KEY" => "secret" }
    with_env(env) do
      get new_user_registration_path
      assert_select ".cf-turnstile[data-sitekey='site']"

      failing = Struct.new(:body).new({ success: false }.to_json)
      Net::HTTP.stub(:post_form, failing) do
        assert_no_difference -> { User.count } do
          post user_registration_path, params: signup_params.merge(human_signup_fields).merge("cf-turnstile-response" => "tok")
        end
      end

      passing = Struct.new(:body).new({ success: true }.to_json)
      Net::HTTP.stub(:post_form, passing) do
        assert_difference -> { User.count }, 1 do
          post user_registration_path, params: signup_params.merge(human_signup_fields).merge("cf-turnstile-response" => "tok")
        end
      end
    end
  end

  test "sign-ups are rate limited per IP" do
    honeypot = { SignupGuard::HONEYPOT_PARAM => "x" } # rejected sign-ups still count
    10.times do |i|
      post user_registration_path, params: signup_params(username: "rl_user#{i}", email: "rl#{i}@example.com").merge(human_signup_fields).merge(honeypot)
    end
    post user_registration_path, params: signup_params(username: "rl_last", email: "rl-last@example.com").merge(human_signup_fields)
    assert_response :too_many_requests
  end

  # ── 6. Account linking ──

  test "Google sign-in linking a password account switches the old password off and emails the owner" do
    auth = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "g-link", info: { email: @author.email, name: "A" })
    user = nil
    assert_enqueued_emails 1 do
      user = User.from_google(auth)
    end
    assert_equal @author.id, user.id
    assert_not user.reload.valid_password?(@pass), "the pre-existing password must stop working"
    assert_nil user.password_chosen_at

    # Signing in again with Google later doesn't rotate anything or email again.
    assert_enqueued_emails 0 do
      assert_equal user.id, User.from_google(auth).id
    end
  end

  test "an unverified Google email is never linked to an existing account" do
    auth = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: "g-unverified", info: { email: @author.email },
                                  extra: { raw_info: { email_verified: false } })
    assert_raises(ActiveRecord::RecordInvalid) { User.from_google(auth) }
    assert @author.reload.valid_password?(@pass)
    assert_nil @author.provider
  end

  # ── 7. Admin escalation ──

  test "an admin can't promote, delete, suspend or re-email a super admin or another admin" do
    admin = User.create!(username: "sec_admin", email: "sec-admin@example.com", password: @pass, role: :admin)
    boss  = User.create!(username: "sec_boss", email: "sec-boss@example.com", password: @pass, role: :super_admin)
    peer  = User.create!(username: "sec_peer", email: "sec-peer@example.com", password: @pass, role: :admin)
    sign_in admin

    post suspend_admin_user_path(boss)
    assert boss.reload.active?
    delete admin_user_path(boss)
    assert User.exists?(boss.id)
    patch admin_user_path(boss), params: { user: { email: "mine@example.com" } }
    assert_equal "sec-boss@example.com", boss.reload.email
    post suspend_admin_user_path(peer)
    assert peer.reload.active?

    post make_admin_admin_user_path(@reader)
    assert @reader.reload.member?
    post make_moderator_admin_user_path(@reader)
    assert @reader.reload.member?
    delete admin_user_path(@reader)
    assert User.exists?(@reader.id)
    patch admin_user_path(@reader), params: { user: { email: "taken@example.com" } }
    assert_equal "sec-reader@example.com", @reader.reload.email

    # Admins can still suspend ordinary members.
    post suspend_admin_user_path(@reader)
    assert_not @reader.reload.active?

    sign_in boss
    post make_moderator_admin_user_path(@reader)
    assert @reader.reload.moderator?
  end

  # ── 8. Private rooms ──

  test "a private room 404s for non-members, and can't be joined by slug" do
    secret = Room.create!(name: "Inner Room", description: "x", is_public: false)
    get room_path(secret)
    assert_response :not_found
    get room_posts_path(secret)
    assert_response :not_found

    sign_in_and_settle @reader
    get room_path(secret)
    assert_response :not_found
    post join_room_path(secret)
    assert_response :not_found
    assert_not secret.room_memberships.exists?(user: @reader)

    secret.room_memberships.create!(user: @author)
    sign_in @author
    get room_path(secret)
    assert_response :success
  end

  # ── 9. Search oracles ──

  test "member search never matches email or private profiles' details" do
    hidden = User.create!(username: "quiet_one", email: "quiet-unique@example.com", password: @pass)
    hidden.profile.update!(bio: "Lives in Narnia", public_profile: false)
    open_user = User.create!(username: "open_one", email: "open-one@example.com", password: @pass)
    open_user.profile.update!(bio: "Lives in Narnia too")

    get search_path(q: "Narnia", type: "users")
    assert_redirected_to new_user_session_path

    sign_in @reader
    get search_path(q: "Narnia", type: "users")
    assert_match(/open_one/, response.body)
    assert_no_match(/quiet_one/, response.body)

    get people_path(q: "quiet-unique@")
    assert_no_match(/quiet_one/, response.body)
    get people_path(q: "Narnia")
    assert_no_match(/quiet_one/, response.body)
  end

  test "inviting an existing member gets the same answer as a new address" do
    sign_in @reader
    post invitations_path, params: { invitation: { email: "brand-new@example.com" } }
    new_notice = flash[:notice].sub("brand-new@example.com", "X")
    post invitations_path, params: { invitation: { email: @author.email } }
    assert_redirected_to invitations_path
    assert_equal new_notice, flash[:notice].sub(@author.email, "X")
  end

  # ── 10. Small ones ──

  test "sensitive params are filtered from logs" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter("body" => "a", "content" => "b", "message" => "c", "details" => "d",
                             "authorization_code" => "e", "current_password" => "f", "code" => "g")
    assert filtered.values.all?("[FILTERED]"), filtered.inspect
  end

  private

  def comments_path_for(post) = post_comments_path(post)

  # Devise's test sign-in lands on the next request; if that request is a 404
  # the session never gets written, so make one ordinary request first.
  def sign_in_and_settle(user)
    sign_in user
    get edit_settings_account_path
    assert_response :success
  end

  def with_env(vars)
    old = vars.keys.index_with { |k| ENV[k] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end

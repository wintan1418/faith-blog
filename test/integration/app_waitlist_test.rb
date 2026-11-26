# frozen_string_literal: true

require "test_helper"

# "Get the app" on the welcome page: POST /waitlist, open to signed-out
# visitors, guarded like sign-up (honeypot + form time) plus a per-IP limit.
class AppWaitlistTest < ActionDispatch::IntegrationTest
  TURBO = { "Accept" => "text/vnd.turbo-stream.html, text/html, application/xhtml+xml" }.freeze

  def waitlist_params(email: "grace@example.com", platform: "android", **extra)
    { app_waitlist_entry: { email: email, platform: platform, source: "welcome" } }.merge(human_signup_fields).merge(extra)
  end

  test "joining with Turbo swaps the form for a thank-you" do
    assert_difference "AppWaitlistEntry.count", 1 do
      post waitlist_path, params: waitlist_params(email: " Grace@Example.com "), headers: TURBO
    end

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_select "turbo-stream[action=replace][target=app_waitlist]" do
      assert_select "template .waitlist-thanks[role=status]", text: /You're on the list\./
      assert_select "template", text: /We'll email grace@example.com when Brethreign is on Android\./
    end
    entry = AppWaitlistEntry.last
    assert_equal [ "grace@example.com", "android", "welcome" ], [ entry.email, entry.platform, entry.source ]
    assert entry.ip_hash.present?
  end

  test "joining without JavaScript redirects to the welcome page with a flash" do
    post waitlist_path, params: waitlist_params(platform: "both")

    assert_redirected_to root_path(anchor: "get-the-app")
    assert_equal "You're on the list. We'll email grace@example.com when Brethreign is on both iPhone and Android.", flash[:notice]
    follow_redirect!
    assert_select "#flash_messages", text: /You're on the list/
  end

  test "the same email again updates the platform" do
    post waitlist_path, params: waitlist_params(platform: "android"), headers: TURBO
    assert_no_difference "AppWaitlistEntry.count" do
      post waitlist_path, params: waitlist_params(email: "GRACE@example.com", platform: "ios"), headers: TURBO
    end
    assert_response :success
    assert_equal "ios", AppWaitlistEntry.find_by(email: "grace@example.com").platform
    assert_select "template", text: /when Brethreign is on iPhone\./
  end

  test "a bad email re-renders the form with an inline error" do
    assert_no_difference "AppWaitlistEntry.count" do
      post waitlist_path, params: waitlist_params(email: "nope@nowhere"), headers: TURBO
    end

    assert_response :unprocessable_entity
    assert_select "turbo-stream[action=replace][target=app_waitlist] template" do
      assert_select "#waitlist_error[role=alert]", text: "Email doesn't look right. Please check it."
      assert_select "input#waitlist_email[aria-invalid=true][value=?]", "nope@nowhere"
      assert_select "input#waitlist_platform_android[checked]"
    end
  end

  test "a bad email without JavaScript redirects back with the error" do
    post waitlist_path, params: waitlist_params(email: "someone@mailinator.com")
    assert_redirected_to root_path(anchor: "get-the-app")
    assert_match "throwaway", flash[:alert]
  end

  test "the honeypot and a too-fast or missing form stamp are turned away" do
    bots = [
      waitlist_params(SignupGuard::HONEYPOT_PARAM => "http://spam.example"),
      waitlist_params.merge(SignupGuard::TOKEN_PARAM => SignupGuard.form_token(issued_at: Time.current)),
      waitlist_params.except(SignupGuard::TOKEN_PARAM)
    ]
    assert_no_difference "AppWaitlistEntry.count" do
      bots.each do |params|
        post waitlist_path, params: params, headers: TURBO
        assert_response :unprocessable_entity
        assert_select "#waitlist_error", text: AppWaitlistEntriesController::BOT_MESSAGE
      end
    end
  end

  test "the waitlist doesn't need Turnstile even when sign-up uses it" do
    with_env("TURNSTILE_SITE_KEY" => "site", "TURNSTILE_SECRET_KEY" => "secret") do
      assert_difference "AppWaitlistEntry.count", 1 do
        post waitlist_path, params: waitlist_params, headers: TURBO
      end
    end
  end

  test "too many tries from one IP are rate limited (15 in 10 minutes)" do
    15.times { |i| post waitlist_path, params: waitlist_params(email: "p#{i}@example.com"), headers: TURBO }
    assert_response :success

    assert_no_difference "AppWaitlistEntry.count" do
      post waitlist_path, params: waitlist_params(email: "p9@example.com"), headers: TURBO
    end
    assert_response :too_many_requests
    assert_select "#waitlist_error", text: AppWaitlistEntriesController::RATE_MESSAGE
  end

  test "signed-in members can join too" do
    sign_in create_member("waitlist_member")
    post waitlist_path, params: waitlist_params(email: "member@example.com"), headers: TURBO
    assert_response :success
    assert AppWaitlistEntry.exists?(email: "member@example.com")
  end

  private

  def with_env(vars)
    old = vars.keys.index_with { |k| ENV[k] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
  test "the shareable /waitlist page shows the form to guests and members" do
    get join_waitlist_path(ref: "wintan")
    assert_response :success
    assert_select "form.waitlist-form input[name='app_waitlist_entry[source]'][value='link:wintan']"

    sign_in users(:one) if respond_to?(:sign_in) && defined?(users)
    get "/waitlist"
    assert_response :success
    assert_select "form.waitlist-form"
  end

  test "/app redirects to the waitlist" do
    get "/app"
    assert_redirected_to "/waitlist"
  end
  test "store badges turn into download links once the store URL is set" do
    ENV["IOS_STORE_URL"] = "https://apps.apple.com/app/brethreign/id6835821959"
    get join_waitlist_path
    assert_select "a.app-badge-get[href='https://apps.apple.com/app/brethreign/id6835821959']"
    assert_select "meta[name='apple-itunes-app'][content='app-id=6835821959']"
    assert_select ".app-badge-soon", text: "Coming soon", count: 1
  ensure
    ENV.delete("IOS_STORE_URL")
  end

  test "joining queues a confirmation email" do
    assert_enqueued_with(job: WaitlistConfirmationJob) do
      post waitlist_path, params: waitlist_params, headers: TURBO
    end
  end

  test "the leave link asks first, then removes the email" do
    entry = AppWaitlistEntry.create!(email: "leaving@example.com", platform: "ios")
    get leave_waitlist_path(token: entry.leave_token)
    assert_response :success
    assert_includes response.body, "leaving@example.com"
    assert AppWaitlistEntry.exists?(entry.id)

    post leave_waitlist_path(token: entry.leave_token)
    assert_response :success
    assert_includes response.body, "You've left the waitlist."
    assert_not AppWaitlistEntry.exists?(entry.id)
  end

  test "a bad leave link removes no one" do
    entry = AppWaitlistEntry.create!(email: "staying@example.com", platform: "ios")
    post leave_waitlist_path(token: "nope")
    assert_response :success
    assert AppWaitlistEntry.exists?(entry.id)
  end
end

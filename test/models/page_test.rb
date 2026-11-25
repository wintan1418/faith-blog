# frozen_string_literal: true

require "test_helper"

# Pages: handles, who may make one, the team, following, posting as a page,
# verification and suspension.
class PageTest < ActiveSupport::TestCase
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @owner = create_member("pg_owner", created_at: 30.days.ago, email_verified_at: Time.current)
    @page = make_page(@owner, "Grace Chapel", "gracechapel")
  end

  teardown { ENV.delete("AI_MODERATION_STUB") }

  def make_page(owner, name, handle, **attrs)
    page = Page.create!(name: name, handle: handle, category: "church", created_by: owner, **attrs)
    page.memberships.create!(user: owner, role: :owner, status: :active)
    page
  end

  def page_post(page, user, **attrs)
    Post.create!({ user: user, page: page, title: "News from #{page.name}", content: "Hello from the page.",
                   status: :published, moderation_status: :approved }.merge(attrs))
  end

  test "handles: format, reserved words, famous names, usernames and case-insensitive uniqueness" do
    [ "ab", "has space", "dash-ed", "x" * 31 ].each do |bad|
      assert_not Page.new(name: "Okay Name", handle: bad).valid?, bad
    end
    %w[admin support help official brethreign].each do |reserved|
      page = Page.new(name: "Okay Name", handle: reserved)
      assert_not page.valid?
      assert_includes page.errors[:handle], "is reserved"
    end
    assert_not Page.new(name: "Okay Name", handle: "rccg_akure").valid?, "famous church handles are protected"
    assert_not Page.new(name: "Okay Name", handle: "PG_Owner").valid?, "a member's username can't be a page handle"
    assert_not Page.new(name: "Okay Name", handle: "GraceChapel").valid?, "handles are unique ignoring case"
    assert Page.new(name: "Okay Name", handle: "@okay_name_2").tap(&:valid?).handle == "okay_name_2"
  end

  test "names can't claim to be official or Brethreign; staff can" do
    assert_not Page.new(name: "Official Grace", handle: "gracex").valid?
    assert_not Page.new(name: "Brethreign Fans", handle: "fansx").valid?
    staff = Page.new(name: "Brethreign", handle: "brethreign", staff_override: true)
    assert staff.valid?, staff.errors.full_messages.to_sentence
  end

  test "famous names are flagged for admins" do
    assert Page.new(name: "Redeemed Christian Church of God, Akure", handle: "x").protected_name?
    assert Page.new(name: "MFM Ondo", handle: "x").protected_name?
    assert_not @page.protected_name?
  end

  test "who may make a page: age or a proven email, adults, at most three owned" do
    fresh = create_member("pg_fresh")
    assert_equal Page::VERIFY_EMAIL_REASON, Page.creation_block_reason(fresh), "an unverified email verifies first"
    fresh.mark_email_verified!
    assert_match(/after 7 days/, Page.creation_block_reason(fresh))
    fresh.update_columns(provider: "google_oauth2", uid: "123")
    assert_nil Page.creation_block_reason(fresh.reload), "Google / Apple sign-ups can make one straight away"

    assert_nil Page.creation_block_reason(@owner)
    make_page(@owner, "Second Place", "secondplace")
    make_page(@owner, "Third Place", "thirdplace")
    assert_match(/already own 3/, Page.creation_block_reason(@owner))

    teen = create_member("pg_teen", created_at: 30.days.ago, email_verified_at: Time.current)
    teen.profile.update_columns(birth_year: Date.current.year - 15)
    assert_match(/18/, Page.creation_block_reason(teen.reload))
  end

  test "roles: owner manages, editors post, pending invites do nothing" do
    editor = create_member("pg_editor")
    invite = @page.memberships.create!(user: editor, role: :editor, status: :pending, invited_by: @owner)
    assert_not @page.editor?(editor)
    invite.accept!
    page = Page.find(@page.id)
    assert page.editor?(editor)
    assert_not page.manager?(editor)
    assert page.manager?(@owner)
    assert page.owner?(@owner)
    assert_includes editor.reload.postable_pages, page
  end

  test "posting as a page needs a role on it, and is never anonymous" do
    stranger = create_member("pg_stranger")
    post = Post.new(user: stranger, page: @page, content: "Not mine", status: :published)
    assert_not post.valid?
    assert_includes post.errors.full_messages.join, "only post as a page you help run"

    anon = Post.new(user: @owner, page: @page, content: "Hidden?", anonymous: true, status: :published)
    assert_not anon.valid?

    post = page_post(@page, @owner)
    assert post.page_post?
    assert_equal "Grace Chapel", post.author_name
  end

  test "page posts don't alert the writer's followers and aren't on the writer's profile" do
    fan = create_member("pg_fan")
    fan.follow(@owner)
    post = nil
    assert_no_difference -> { Notification.where(user: fan, notification_type: :breath_from_followee).count } do
      post = page_post(@page, @owner)
      BreathFanoutJob.perform_now(post.id)
    end
    assert_not_includes @owner.posts.published.personal, post
  end

  test "following counts up, and managers get one alert a day however many follow" do
    a = create_member("pg_follower_a")
    b = create_member("pg_follower_b")
    PageFollow.create!(page: @page, user: a)
    PageFollow.create!(page: @page, user: b)
    assert_equal 2, @page.reload.followers_count
    alerts = Notification.where(user: @owner, notification_type: :page_new_follower)
    assert_equal 1, alerts.count
    assert_equal "pg_follower_a and 1 other followed “Grace Chapel”", alerts.first.web_message
    assert_equal "/p/gracechapel", alerts.first.target_path
  end

  test "verification and suspension" do
    @page.request_verification!("Our website lists this page.")
    assert @page.verification_requested?
    admin = create_member("pg_admin", role: :admin)
    @page.verify!(admin)
    assert @page.verified?
    assert Notification.exists?(user: @owner, notification_type: :page_verified)

    post = page_post(@page, @owner)
    assert_includes Post.published, post
    @page.suspend!
    assert_not_includes Post.published, post
    assert_not post.reload.feed_visible?
    assert_not @page.visible_to?(create_member("pg_reader"))
    assert @page.visible_to?(@owner)
    @page.reinstate!
    assert_includes Post.published, post
  end

  test "search: a page post is indexed under the page, not the writer" do
    post = page_post(@page, @owner, title: "Prayer night")
    vector = Post.where(id: post.id).pick(Arel.sql("searchable::text"))
    assert_includes vector, "grace"
    assert_not_includes vector, "pg_owner"
    page_vector = Page.where(id: @page.id).pick(Arel.sql("searchable::text"))
    assert_includes page_vector, "church"
    @page.update!(name: "Hope Chapel")
    assert_includes Post.where(id: post.id).pick(Arel.sql("searchable::text")), "hope"
  end

  test "an experience links to a page and lists the member only when they say so" do
    member = create_member("pg_member")
    job = member.experiences.create!(title: "Usher", organization: "Grace Chapel", start_on: 1.year.ago, page_handle: "@gracechapel")
    assert_equal @page, job.page
    assert_empty Experience.listed_for_page(@page)
    job.update!(listed_on_page: true)
    assert_equal [ job ], Experience.listed_for_page(@page).to_a
    bad = member.experiences.new(title: "X", organization: "Y", start_on: 1.year.ago, page_handle: "nosuchpage")
    assert_not bad.valid?
  end

  test "mentioning a page tells its managers" do
    other_owner = create_member("pg_other", created_at: 30.days.ago)
    Post.create!(user: other_owner, content: "Thank you @gracechapel for hosting us", status: :published, moderation_status: :approved)
    alert = Notification.find_by(user: @owner, notification_type: :page_mentioned)
    assert alert
    assert_equal "pg_other mentioned your page", alert.web_message
  end
end

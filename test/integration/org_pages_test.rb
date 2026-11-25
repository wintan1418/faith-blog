# frozen_string_literal: true

require "test_helper"

# Pages end to end: the directory, making a page, its profile and tabs,
# following, the team, posting as the page, feeds, search, admin, reports,
# SEO and the apps.
class OrgPagesTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    seen = { welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i, created_at: 30.days.ago }
    @owner = create_member("op_owner", **seen)
    @editor = create_member("op_editor", **seen)
    @reader = create_member("op_reader", **seen)
    @page = Page.create!(name: "Grace Chapel", handle: "gracechapel", category: "church", tagline: "A family church",
                         city: cities(:akure), website: "gracechapel.org", service_times: "Sundays 9am", created_by: @owner)
    @page.memberships.create!(user: @owner, role: :owner, status: :active)
  end

  teardown { ENV.delete("AI_MODERATION_STUB") }

  def page_post(user = @owner, **attrs)
    Post.create!({ user: user, page: @page, title: "Sunday service", content: "Join us this Sunday.",
                   status: :published, moderation_status: :approved }.merge(attrs))
  end

  test "signed out: the page, its tabs, JSON-LD, the OG card and the sitemap" do
    page_post
    get org_page_path(@page)
    assert_response :success
    assert_select "h1.pg-name", text: /Grace Chapel/
    assert_select ".pg-card, article.fc-breath", minimum: 1
    assert_select "script[type='application/ld+json']", text: /"@type":"Church"/
    assert_select "meta[property='og:image'][content*='/og/pages/gracechapel.jpg']"
    assert_select "link[rel=canonical][href$='/p/gracechapel']"
    get about_org_page_path(@page)
    assert_select ".pg-times li", text: "Sundays 9am"
    assert_select "a[href='https://gracechapel.org']"
    get people_org_page_path(@page)
    assert_response :success

    get page_og_image_path(@page, format: :jpg)
    assert_response :success
    assert_equal "image/jpeg", response.media_type

    get pages_sitemap_path
    assert_includes response.body, "/p/gracechapel"
  end

  test "directory: categories, search and near you" do
    sign_in @reader
    @reader.profile.update_columns(city_id: cities(:akure).id)
    get pages_directory_path
    assert_select "#pg-near ~ .pg-cards .pg-card", text: /Grace Chapel/
    get pages_directory_path(category: "church")
    assert_select ".pg-card", text: /Grace Chapel/
    get pages_directory_path(category: "business")
    assert_select ".pg-card", count: 0
    get pages_directory_path(q: "family")
    assert_select ".pg-card", text: /Grace Chapel/
  end

  test "making a page: the creator becomes its owner; new accounts wait" do
    sign_in @reader
    assert_difference -> { Page.count } do
      post org_pages_path, params: { page: { name: "Hope Fellowship", handle: "hopefellowship", category: "fellowship",
                                             tagline: "Students growing together", city_id: cities(:akure).id,
                                             logo: Rack::Test::UploadedFile.new(Rails.root.join("public/apple-touch-icon.png"), "image/png") } }
    end
    page = Page.find_by_handle!("hopefellowship")
    assert_redirected_to org_page_path(page)
    assert page.owner?(@reader)
    assert page.logo.attached?

    post org_pages_path, params: { page: { name: "Taken", handle: "HopeFellowship", category: "church" } }
    assert_response :unprocessable_entity

    newbie = create_member("op_newbie")
    sign_in newbie
    get new_org_page_path
    assert_select ".pg-blocked", text: /after 7 days/
    assert_no_difference -> { Page.count } do
      post org_pages_path, params: { page: { name: "Too Soon", handle: "toosoon", category: "church" } }
    end
  end

  test "handle check says what's free" do
    sign_in @reader
    get org_page_handle_check_path(handle: "gracechapel")
    assert_equal false, response.parsed_body["available"]
    get org_page_handle_check_path(handle: "admin")
    assert_match(/reserved/, response.parsed_body["message"])
    get org_page_handle_check_path(handle: "brandnew", name: "Brand New Church")
    assert response.parsed_body["available"]
    assert_equal "brandnewchurch", response.parsed_body["suggestion"]
  end

  test "follow and unfollow (in place), and the page's posts reach the Following feed" do
    post_as_page = page_post
    sign_in @reader
    post org_page_follow_path(@page), as: :turbo_stream
    assert_response :success
    assert_includes response.body, "Following"
    assert @page.followed_by?(@reader)

    get feed_following_path
    assert_select "article##{ActionView::RecordIdentifier.dom_id(post_as_page)}" do
      assert_select ".pg-chip", text: "Page"
      assert_select ".fc-breath-name", text: "Grace Chapel"
    end
    assert_not_includes response.body, "@op_owner"

    delete org_page_follow_path(@page)
    assert_not @page.followed_by?(@reader)
  end

  test "signed-out Follow goes through sign-up" do
    post org_page_follow_path(@page)
    assert_redirected_to new_user_registration_path
  end

  test "the team: invite, accept, post as the page, change role, remove, transfer" do
    sign_in @owner
    post org_page_team_path(@page), params: { username: "@op_editor", role: "editor" }
    invite = @page.memberships.find_by!(user: @editor)
    assert invite.pending?
    assert Notification.exists?(user: @editor, notification_type: :page_invite)
    post org_page_team_path(@page), params: { username: "nobody_here" }
    assert_match(/couldn't find/, flash[:alert])

    sign_in @editor
    get org_page_path(@page)
    assert_select ".pg-banner", text: /invited you/
    post accept_org_page_invite_path(@page, invite)
    assert invite.reload.active?

    get new_post_path(as: "gracechapel")
    assert_select "select[name='post[page_id]'] option[selected][value='#{@page.id}']"
    post posts_path, params: { post: { title: "Prayer night", content: "Friday at 7.", page_id: @page.id,
                                        kind: "breath", prayer_status: "not_a_prayer", status: "published" } }
    written = Post.order(:id).last
    assert_equal @page, written.page
    assert_equal @editor, written.user, "the writer is kept for moderation"
    follow_redirect!
    assert_select ".post-author-row", text: /Grace Chapel/
    assert_select ".post-author-row", text: /op_editor/, count: 0

    get manage_org_page_path(@page)
    assert_redirected_to org_page_path(@page), "editors can't manage"

    sign_in @owner
    patch org_page_team_member_path(@page, invite), params: { role: "admin" }
    assert invite.reload.admin?
    post transfer_org_page_path(@page), params: { username: "op_editor" }
    assert @page.reload.owner?(@editor)
    assert @page.manager?(@owner)

    sign_in @editor
    delete org_page_team_member_path(@page, @page.memberships.find_by!(user: @owner))
    assert_nil @page.memberships.find_by(user: @owner)
  end

  test "someone off the team can't post as the page" do
    sign_in @reader
    post posts_path, params: { post: { content: "Sneaky", page_id: @page.id, kind: "breath", prayer_status: "not_a_prayer", status: "published" } }
    assert_nil Post.order(:id).last.page_id
  end

  test "managing: edit details, ask for verification; strangers can't" do
    sign_in @reader
    get manage_org_page_path(@page)
    assert_redirected_to org_page_path(@page)
    patch org_page_path(@page), params: { page: { name: "Hijack" } }
    assert_equal "Grace Chapel", @page.reload.name

    sign_in @owner
    get manage_org_page_path(@page)
    assert_response :success
    patch org_page_path(@page), params: { page: { tagline: "New words", phone: "+234 800 000 0000" } }
    assert_equal "New words", @page.reload.tagline
    post org_page_verification_path(@page), params: { note: "Our site links to this page." }
    assert @page.reload.verification_requested?
  end

  test "admin: list requests, verify, suspend; reports on pages" do
    @page.request_verification!("Please verify us, link on our site.")
    sign_in @reader
    post reports_path, params: { reportable_type: "Page", reportable_id: @page.id, reason: "Pretending to be another church." }
    assert Report.exists?(reportable: @page)

    admin = create_member("op_admin", role: :admin)
    sign_in admin
    get admin_pages_path(filter: "requests")
    assert_select "#admin-pages", text: /Grace Chapel/
    get admin_page_path(@page)
    assert_select "li", text: /Pretending/
    post verify_admin_page_path(@page)
    assert @page.reload.verified?
    post suspend_admin_page_path(@page)
    assert @page.reload.suspended?

    sign_in @reader
    get org_page_path(@page)
    assert_response :not_found
  end

  test "search: the Pages tab and the top results" do
    get search_path(q: "grace", tab: "pages")
    assert_select ".srch-page", text: /Grace Chapel/
    get search_path(q: "akure church")
    assert_select ".srch-page", text: /Grace Chapel/
  end

  test "a member's profile can link a role to a page and show them on its People tab" do
    sign_in @reader
    post settings_experiences_path, params: { experience: { title: "Choir", organization: "Grace Chapel", start_month: "2023-01",
                                                            current: "1", page_handle: "gracechapel", listed_on_page: "1" } }
    get people_org_page_path(@page)
    assert_select ".pg-person", text: /op_reader/
    get user_path("op_reader", tab: "professional")
    assert_select "a[href='/p/gracechapel']"
  end

  test "in the apps the title is the page's name" do
    get org_page_path(@page), headers: { "User-Agent" => "Hotwire Native iOS; Turbo Native iOS" }
    assert_select "title", "Grace Chapel"
  end

  test "share card data shows the page, not the writer" do
    post_as_page = page_post
    get post_share_card_path(post_as_page)
    author = response.parsed_body["author"]
    assert_equal "Grace Chapel", author["name"]
    assert_equal "gracechapel", author["username"]
  end

  test "@handle of a page links to the page" do
    mention = Post.create!(user: @reader, content: "Thank you @gracechapel for Sunday", status: :published, moderation_status: :approved)
    get post_path(mention)
    assert_select "a.mention-link.is-page[href='/p/gracechapel']", text: "@gracechapel"
  end
end

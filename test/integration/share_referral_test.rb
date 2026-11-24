# frozen_string_literal: true

require "test_helper"

# Shared breaths carry ?ref=<sharer>: a signed-out visitor is greeted with the
# sharer's name and the sharer is remembered for the invite credit
# (ShareReferral → InviteAttribution → users.invited_by_id → Seeds).
class ShareReferralTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @ada = create_member("ada_shares")
    @author = create_member("breath_author")
    @post = Post.create!(user: @author, title: "Rest is obedience", content: "Rest is obedience, not laziness.",
                         status: :published, moderation_status: :approved, published_at: 1.hour.ago)
  end

  def banner = ".share-invite"
  def ref_cookie = cookies[InviteAttribution::COOKIE.to_s]

  test "a guest on a shared breath sees who invited them and the sharer is remembered" do
    get post_path(@post, ref: @ada.username)

    assert_response :success
    assert_select banner, text: /ada_shares\s+invited you to the conversation on Brethreign/
    assert_select "#{banner} a[href='#{new_user_registration_path}']", text: "Join free"
    assert ref_cookie.present?
  end

  test "a guest who joins after a shared link is credited to the sharer" do
    get post_path(@post, ref: @ada.username)
    post user_registration_path, params: { user: { username: "new_friend", email: "new_friend@example.com",
                                                   password: SecureRandom.base58(16) } }.merge(human_signup_fields)

    assert_equal @ada.id, User.find_by!(username: "new_friend").invited_by_id
  end

  test "banned, restricted, inactive, under-18 and unknown sharers are neither named nor credited" do
    banned = create_member("banned_sharer")
    banned.risk_profile.update!(risk_level: :banned)
    restricted = create_member("restricted_sharer")
    restricted.risk_profile.update!(risk_level: :restricted)
    inactive = create_member("inactive_sharer", active: false)
    minor = create_member("minor_sharer")
    minor.profile.update!(birth_year: Date.current.year - 15)

    [ banned.username, restricted.username, inactive.username, minor.username, "nobody_at_all", "x<script>", "a" ].each do |ref|
      cookies.delete(InviteAttribution::COOKIE.to_s)
      get post_path(@post, ref: ref)
      assert_response :success
      assert_select banner, 0, "#{ref} should not be greeted"
      assert_predicate ref_cookie, :blank?, "#{ref} should not be credited"
    end
  end

  test "a ref never replaces an invite the visitor already carries" do
    first = create_member("first_inviter")
    get join_invite_path(first.username)
    remembered = ref_cookie

    get post_path(@post, ref: @ada.username)
    assert_select banner, 1
    assert_equal remembered, ref_cookie

    post user_registration_path, params: { user: { username: "kept_friend", email: "kept_friend@example.com",
                                                   password: SecureRandom.base58(16) } }.merge(human_signup_fields)
    assert_equal first.id, User.find_by!(username: "kept_friend").invited_by_id
  end

  test "one address can only set the invite cookie a few times" do
    ShareReferral::CAPTURE_LIMIT.times do
      cookies.delete(InviteAttribution::COOKIE.to_s)
      get post_path(@post, ref: @ada.username)
      assert ref_cookie.present?
    end
    cookies.delete(InviteAttribution::COOKIE.to_s)
    get post_path(@post, ref: @ada.username)
    assert_predicate ref_cookie, :blank?
  end

  test "the author of an anonymous breath is never named on it, even by their own link" do
    secret = Post.create!(user: @author, title: "Please pray", content: "Something hard to say out loud.", anonymous: true,
                          status: :published, moderation_status: :approved, published_at: 1.hour.ago)

    get post_path(secret, ref: @author.username)
    assert_select banner, 0
    assert_not_includes response.body, @author.username
    assert_nil ShareReferral.ref_for(@author, secret)

    get post_path(secret, ref: @ada.username)
    assert_select banner, 1
  end

  test "members don't see the banner and their own invite state is untouched" do
    sign_in create_member("already_here")
    get post_path(@post, ref: @ada.username)
    assert_select banner, 0
    assert_predicate ref_cookie, :blank?
  end

  test "a held breath doesn't greet or credit anyone" do
    @post.update_columns(moderation_status: Post.moderation_statuses[:pending_review])
    get post_path(@post, ref: @ada.username)
    assert_predicate ref_cookie, :blank?
  end

  test "members can't invite by link once restricted" do
    assert @ada.can_invite_by_link?
    @ada.risk_profile.update!(risk_level: :restricted)
    assert_not @ada.reload.can_invite_by_link?
  end

  test "share links carry the signed-in sharer's ref" do
    sign_in @ada
    get post_path(@post)
    assert_select ".fc-share[data-share-url-value='#{post_url(@post, ref: @ada.username)}']"
  end

  test "the short link opens the breath with the ref, and hides what isn't public" do
    get short_post_path(code: @post.id.to_s(36), ref: @ada.username)
    assert_redirected_to post_path(@post, ref: @ada.username)

    get short_post_path(code: @post.id.to_s(36))
    assert_redirected_to post_path(@post)

    draft = Post.create!(user: @author, title: "Draft", content: "Not yet", status: :draft)
    get short_post_path(code: draft.id.to_s(36))
    assert_redirected_to root_path

    get short_post_path(code: "zzzzzz")
    assert_redirected_to root_path
  end
end

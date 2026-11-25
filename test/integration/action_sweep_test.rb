# frozen_string_literal: true

require "test_helper"
require_relative "../support/sweep_world"

# The everyday actions, done the way the app's forms and buttons do them, end
# to end through real requests: each must land (no 500) and do its job.
class ActionSweepTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include SweepWorld
  include KlipyStubs

  setup do
    @stub_was = ENV["AI_MODERATION_STUB"]
    ENV["AI_MODERATION_STUB"] = "1"
    build_sweep_world
  end

  teardown { ENV["AI_MODERATION_STUB"] = @stub_was }

  def ok!(label = nil)
    assert_operator response.status, :<, 500, "#{label || request.path} answered #{response.status}"
  end

  def as(user)
    sign_in User.find(user.id)
  end

  test "posts: create (image, anonymous, thread, scheduled, draft), publish a draft, edit, delete" do
    as @member
    assert_difference -> { @member.posts.count }, 5 do
      post posts_path, params: { post: { content: "A breath with a picture.", images: [ png_upload ] } }
      ok!
      post posts_path, params: { post: { content: "Quietly thankful today.", anonymous: "1" } }
      ok!
      post posts_path, params: { post: { kind: "thread", title: "Let us talk about rest", content: "What does Sabbath rest look like for you?" } }
      ok!
      post posts_path, params: { post: { content: "Tomorrow's word.", scheduled_for: 1.day.from_now.iso8601 } }
      ok!
      post posts_path, params: { post: { content: "Half written.", status: "draft" } }
      ok!
    end
    newest = @member.posts.order(:id).last(5)
    assert newest.first.images.attached?
    assert newest.second.anonymous?
    assert newest.third.kind_thread?
    assert newest.fourth.scheduled?
    assert newest.fifth.draft?

    patch post_path(@draft), params: { post: { content: "Finished now.", status: "published" } }
    ok!
    assert @draft.reload.published?

    patch post_path(@post), params: { post: { content: "Grace and peace, edited." } }
    ok!
    assert_equal "Grace and peace, edited.", @post.reload.content.to_plain_text

    patch post_path(@post), params: { post: { content: "Edited again", status: "nonsense" } }
    assert_includes 400..499, response.status, "an unknown status is refused, not a crash"

    delete post_path(@thread)
    ok!
    assert_not Post.exists?(@thread.id)
  end

  test "comments: comment, reply, edit, delete" do
    as @other
    assert_difference -> { @post.comments.count }, 2 do
      post post_comments_path(@post), params: { comment: { content: "Amen, brother." } }
      ok!
      post reply_post_comment_path(@post, @comment), params: { comment: { content: "Yes and amen." } }
      ok!
    end
    patch post_comment_path(@post, @comment), params: { comment: { content: "Amen, edited." } }, as: :turbo_stream
    ok!
    delete post_comment_path(@post, @comment)
    ok!
  end

  test "reactions, intercession, repost, quote, save, report" do
    as @other
    delete unlike_path(likeable_type: "Post", likeable_id: @post.id)
    ok!
    post likes_path(likeable_type: "Post", likeable_id: @post.id), params: { reaction_type: "praying" }
    ok!
    post likes_path(likeable_type: "Comment", likeable_id: @reply.id), params: { reaction_emoji: "🔥" }
    ok!
    post join_prayer_chain_post_path(@post)
    ok!
    delete post_reshare_path(@post)
    ok!
    post post_reshare_path(@post), params: { reshare: { thought: "Read this today." } }
    ok!
    post posts_path, params: { post: { content: "Quoting this one.", quoted_post_id: @post.id } }
    ok!
    post post_bookmark_path(@post)
    ok!
    delete post_bookmark_path(@post)
    ok!
    post reports_path, params: { reportable_type: "Post", reportable_id: @post.id, reason: "Feels like spam to me." }
    ok!
    post reports_path, params: { reportable_type: "Comment", reportable_id: @reply.id }
    ok!
  end

  test "prayer answered, follow/unfollow, block/unblock" do
    as @other
    post mark_prayer_answered_post_path(@prayer)
    ok!
    delete unfollow_user_path(@member.username)
    ok!
    post follow_user_path(@member.username)
    ok!
    post message_blocks_path(user_id: @member.id)
    ok!
    assert MessageBlock.exists?(blocker: @other, blocked: @member)
    delete message_block_path(@member.id)
    ok!
    assert_not MessageBlock.exists?(blocker: @other, blocked: @member)
  end

  test "messages: send, reply, edit, delete, forward, react, GIF without a key, files" do
    without_klipy_key
    as @member
    post conversation_messages_path(@conversation), params: { message: { body: "Hello again!" } }
    ok!
    post conversation_messages_path(@conversation), params: { message: { body: "Replying.", reply_to_id: @message.id } }
    ok!
    post conversation_messages_path(@conversation), params: { message: { body: "Reply to nothing.", reply_to_id: 0 } }
    ok!("reply to a missing message")
    post conversation_messages_path(@conversation), params: { message: { body: "", gif_url: "https://static.klipy.com/x.gif" } }
    ok!("GIF with no key")
    post conversation_messages_path(@conversation), params: { message: { body: "A photo", images: [ png_upload ] } }
    ok!
    mine = @conversation.messages.where(sender: @member).order(:id).last
    patch conversation_message_path(@conversation, mine), params: { message: { body: "Edited words" } }, as: :turbo_stream
    ok!
    assert_equal "Edited words", mine.reload.body
    patch conversation_message_path(@conversation, mine), params: { message: { body: "x", reply_to_id: 0 } }
    ok!("edit with a stray reply id")
    post likes_path(likeable_type: "Message", likeable_id: @message.id), params: { reaction_emoji: "🙏" }
    ok!
    get forward_conversation_message_path(@conversation, @message)
    ok!
    post forward_conversation_message_path(@conversation, @message), params: { conversation_ids: [ @conversation.id ] }
    ok!
    get conversation_message_file_path(@conversation, @file_message, @file_attachment, filename: "pixel.png")
    ok!
    assert_response :success
    delete conversation_message_path(@conversation, mine)
    ok!
    post conversations_path, params: { recipient_id: @other.id }
    ok!
    post mark_read_conversation_path(@conversation)
    ok!
    post archive_conversation_path(@conversation)
    ok!
  end

  test "rooms and circles: join and leave, breathe, pray, amen" do
    as @other
    post join_room_path(@room)
    ok!
    delete leave_room_path(@room)
    ok!
    post circles_path, params: { circle: { name: "Friday Fellowship" } }
    ok!
    post circle_breaths_path(@circle), params: { circle_breath: { body: "Peace to you all." } }
    ok!
    post circle_prayers_path(@circle), params: { circle_prayer: { title: "Pray for my exams" } }
    ok!
    prayer = @circle.prayers.order(:id).last
    post amen_circle_prayer_path(@circle, prayer)
    ok!
    post answered_circle_prayer_path(@circle, prayer)
    ok!
    get circle_path(@circle)
    assert_response :success
    delete leave_circle_path(@circle)
    ok!
    as @member
    get join_circle_path(@circle.invite_code)
    ok!
    post join_circle_path(@circle.invite_code)
    ok!
  end

  test "settings: profile, notifications on and off, privacy, password change, account delete" do
    password = SecureRandom.base58(16)
    @member.update!(password: password)
    as @member
    patch settings_profile_path, params: { profile: { bio: "Builder and believer.", location: "Lagos" } }
    ok!
    patch settings_notifications_path, params: { email_notifications_enabled: "1" }
    ok!
    assert @member.reload.email_notifications_enabled
    # Unticking the box sends no field at all: that turned into nil and crashed.
    patch settings_notifications_path
    ok!("turning email notifications off")
    assert_not @member.reload.email_notifications_enabled
    patch settings_privacy_path, params: { user: { show_online_status: "0" }, profile: { public_profile: "1" } }
    ok!
    patch settings_dark_mode_path, params: { dark: "1" }
    ok!
    patch settings_background_rain_path, params: { on: "" }, as: :json
    ok!
    new_password = SecureRandom.base58(16)
    @member.mark_email_verified! # changing the password needs a verified email
    patch settings_account_path, params: { user: { password: new_password, password_confirmation: new_password, current_password: password } }
    ok!
    assert @member.reload.valid_password?(new_password)

    as @member
    delete settings_account_path, params: { confirm_username: "wrong" }
    ok!
    assert User.exists?(@member.id)
    delete user_registration_path
    ok!
    assert User.exists?(@member.id), "Devise's DELETE /users must not skip the confirmation"
    delete settings_account_path, params: { confirm_username: @member.username }
    ok!
    assert_not User.exists?(@member.id)
  end

  test "notifications, search, games, reading plans" do
    as @member
    post mark_read_notification_path(@notification)
    ok!
    post mark_all_read_notifications_path
    ok!
    %w[grace @sweep #hope sweep_other].each do |q|
      %w[all posts people rooms].each do |type|
        get search_path(q: q, type: type)
        ok!
      end
    end
    post games_quiz_submit_path, params: { score: 4, max_score: 5, duration_ms: 30_000 }, as: :json
    ok!
    post games_chess_solved_path, as: :json
    ok!
    post games_verse_memory_submit_path, params: { score: 3, max_score: 3, details: { foo: "bar" } }, as: :json
    ok!
    plan = ReadingPlan.all.first
    if plan
      post start_reading_plan_path(plan.slug)
      ok!
      post check_in_reading_plan_path(plan.slug)
      ok!
    end
  end

  test "admin moderation: hold, release, block, decide, reports, suspend" do
    as @admin
    post decide_admin_moderation_review_path(@review), params: { decision: "hide", notes: "Not for the feed." }
    ok!
    post release_post_admin_moderation_reviews_path, params: { post_id: @held.id }
    ok!
    post decide_admin_moderation_review_path(@review), params: { decision: "approve" }
    ok!
    post resolve_admin_report_path(@report)
    ok!
    post dismiss_admin_report_path(@report)
    ok!
    post suspend_admin_user_path(@member)
    ok!
    post activate_admin_user_path(@member)
    ok!
    post feature_admin_post_path(@post)
    ok!
    get admin_user_path(@member)
    assert_redirected_to admin_users_path(q: @member.username)
  end
end

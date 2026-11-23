# frozen_string_literal: true

require "test_helper"

# Seeds in the app: the toast, the rank-up celebration (once), the profile,
# the feed card and the leaderboard.
class SeedsFlowTest < ActionDispatch::IntegrationTest
  LONG = "What a faithful word, thank you for sharing this with us"

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    seen = { welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i,
             tour_completed_at: Time.current, onboarding_dismissed_at: Time.current }
    @author = create_member("flow_author", **seen)
    @me = create_member("flow_me", **seen)
    @room = Room.create!(name: "Flow Room", description: "x", is_public: true)
    @post = Post.create!(user: @author, room: @room, title: "A breath to comment on", content: "Body",
                         status: :published, moderation_status: :approved, published_at: Time.current)
    sign_in @me
  end

  def give(user, points, on: Date.current, anonymous: false, room: nil)
    SeedEvent.create!(user: user, kind: "badge", points: points, source: Room.create!(name: "src #{SecureRandom.hex(4)}", description: "x"),
                      created_on: on, created_at: on.to_time, anonymous: anonymous, room_id: room&.id)
    Seeds.recompute_totals!(user.id)
  end

  test "commenting shows a +5 seeds toast in the Turbo Stream response" do
    post post_comments_path(@post), params: { comment: { content: LONG } }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, %(target="seed_toasts")
    assert_includes response.body, "+5 seeds"
    assert_equal 5, @me.reload.seeds_total
  end

  test "a plain form post carries the toast to the next page" do
    post post_comments_path(@post), params: { comment: { content: LONG } }
    follow_redirect!
    assert_select ".seed-toast", text: /\+5 seeds/
  end

  test "no toast when nothing was earned" do
    post post_comments_path(@post), params: { comment: { content: "Amen" } }, as: :turbo_stream
    assert_response :success
    assert_not_includes response.body, "seed_toasts"
  end

  test "the rank-up celebration shows once, then never again" do
    give(@me, 46)
    post post_comments_path(@post), params: { comment: { content: LONG } }, as: :turbo_stream
    assert_includes response.body, "You're now a Sprout"
    assert Notification.rank_up.exists?(user: @me)

    get feed_path
    assert_select "dialog.seed-rankup", 1

    post seeds_rank_seen_path
    assert_response :no_content
    get feed_path
    assert_select "dialog.seed-rankup", 0
  end

  test "an award failure never breaks the request" do
    Seeds.stub(:award, ->(**) { raise "ledger on fire" }) do
      post post_comments_path(@post), params: { comment: { content: LONG } }, as: :turbo_stream
    end
    assert_response :success
    assert_equal 1, @post.reload.comments_count
  end

  test "your profile shows your rank, seeds and progress; others see the rank and public seeds" do
    give(@me, 160)
    give(@me, 40, anonymous: true)
    get user_path(@me.username)
    assert_select ".seed-rank--profile", text: /Sapling/
    assert_select ".profile-stat-seeds", text: /200/
    assert_select ".seed-profile-progress .seed-progress"

    sign_in @author
    get user_path(@me.username)
    assert_select ".seed-rank--profile", text: /Sapling/
    assert_select ".profile-stat-seeds", text: /160/
    assert_select ".seed-profile-progress", 0
  end

  test "commenters carry a small rank chip, but a masked anonymous author doesn't" do
    anon = Post.create!(user: @author, room: @room, title: "Anon", content: "Hidden", anonymous: true,
                        status: :published, moderation_status: :approved, published_at: Time.current)
    anon.comments.create!(user: @author, content: "From the hidden author here", moderation_status: :approved)
    anon.comments.create!(user: @me, content: LONG, moderation_status: :approved)
    get post_path(anon)
    assert_select ".cm-rank", 1
  end

  test "the feed shows this week's top encouragers" do
    give(@author, 30)
    get feed_path
    assert_select ".seed-side-card .seed-side-row", 1
    assert_select ".seed-side-card", text: /flow_author/
  end

  test "the leaderboard leaves out staff, anonymous-breath seeds, and last week on This week" do
    admin = create_member("flow_admin", role: :admin)
    give(admin, 500)
    give(@author, 20)
    give(@author, 300, anonymous: true)
    old = create_member("flow_old")
    give(old, 90, on: 2.weeks.ago.to_date)

    get leaderboard_path
    assert_select ".seed-board .seed-row", 1
    assert_select ".seed-board", text: /flow_author/
    assert_select ".seed-board", text: /30 seeds/ # 20 + 10 for the breath in setup
    assert_select ".seed-board", { text: /flow_admin/, count: 0 }

    get leaderboard_path(tab: "all")
    assert_select ".seed-board .seed-row", 2
    assert_select ".seed-board .seed-row:first-child", text: /flow_old/

    sign_in admin
    get leaderboard_path
    assert_select ".seed-mine", text: /Staff stay off the public board/
    assert_select ".seed-mine", text: /500 seeds/
  end

  test "the founder gets a pinned, unranked card above the board" do
    founder = create_member("flow_founder", role: :super_admin)
    give(founder, 900)
    give(@author, 20)

    get leaderboard_path(tab: "all")
    assert_select ".seed-founder", 1
    assert_select ".seed-founder", text: /flow_founder/
    assert_select ".seed-founder", text: /900 seeds/
    assert_select ".seed-board", { text: /flow_founder/, count: 0 }
    assert_select ".seed-board .seed-row:first-child .seed-pos", text: "1"

    give(create_member("flow_admin2", role: :admin), 400)
    get leaderboard_path(tab: "all")
    assert_select ".seed-founder", 1 # other admins stay off, with no card
  end

  test "no founder card when the founder has no seeds in that period" do
    create_member("flow_founder", role: :super_admin)
    get leaderboard_path
    assert_select ".seed-founder", 0
  end

  test "the room tab counts only seeds earned in that room" do
    other = Room.create!(name: "Other Room", description: "x", is_public: true)
    give(@author, 20, room: @room)
    give(@me, 40, room: other)
    get leaderboard_path(tab: "room", room: @room.slug)
    assert_select ".seed-board .seed-row", 1
    assert_select ".seed-board", text: /flow_author/
  end

  test "you see your own place even when you're not in the top list" do
    (LeaderboardController::TOP + 1).times { |i| give(create_member("flow_top#{i}"), 100 + i) }
    give(@me, 3) # behind all of them and the setup author's 10
    get leaderboard_path
    assert_select ".seed-board .seed-row", LeaderboardController::TOP
    assert_select ".seed-mine .seed-pos", text: "##{LeaderboardController::TOP + 3}"
  end

  test "the how-to-earn page lists the rules and ranks" do
    get seeds_guide_path
    assert_response :success
    assert_select ".seed-rule", Seeds::RULES.size - 2 # three streak rules share a line
    assert_select ".seed-rank-line", Seeds::Rank.all.size
  end
end

# frozen_string_literal: true

require "test_helper"

# Seeds: each earning rule, its cap, no self-earning, reversals, no double pay.
class SeedsTest < ActiveSupport::TestCase
  LONG = "What a faithful word, thank you for sharing this with us"

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @author = create_member("seed_author")
    @reader = create_member("seed_reader")
    @room = Room.create!(name: "Seeds Room #{SecureRandom.hex(2)}", description: "x", is_public: true)
  end

  def breath(user = @author, **attrs)
    Post.create!({ user: user, room: @room, title: "A breath #{SecureRandom.hex(3)}", content: "Body of the breath",
                   status: :published, moderation_status: :approved, published_at: Time.current }.merge(attrs))
  end

  def comment(post, user = @reader, text = LONG)
    post.comments.create!(user: user, content: text, moderation_status: :approved)
  end

  def kinds(user) = user.seed_events.pluck(:kind).tally

  def total(user) = user.reload.seeds_total

  # ── Earning rules ─────────────────────────────────────────────

  test "publishing a breath pays 10, the first 3 a day" do
    4.times { breath }
    assert_equal 3, kinds(@author)["breath"]
    assert_equal 30, total(@author)
  end

  test "a held or draft breath pays nothing until it goes live" do
    post = breath(status: :draft, published_at: nil)
    assert_equal 0, total(@author)

    post.update!(status: :published)
    assert_equal 10, total(@author)
  end

  test "commenting on someone else's breath pays 5 and the author 2" do
    post = breath
    comment(post)
    assert_equal({ "comment" => 1 }, kinds(@reader))
    assert_equal 1, kinds(@author)["comment_received"]
    assert_equal 5, total(@reader)
    assert_equal 12, total(@author)
  end

  test "a short comment earns the commenter nothing but still counts for the author" do
    post = breath
    comment(post, @reader, "Amen!")
    assert_equal 0, total(@reader)
    assert_equal 1, kinds(@author)["comment_received"]
  end

  test "comments are capped at 20 a day" do
    posts = Array.new(3) { breath }
    22.times { |i| comment(posts[i % 3]) }
    assert_equal 20, kinds(@reader)["comment"]
  end

  test "the author gets the comment-received seeds once per commenter per breath" do
    post = breath
    3.times { comment(post) }
    comment(post, create_member("seed_third"))
    assert_equal 2, kinds(@author)["comment_received"]
  end

  test "no seeds for commenting on, reacting to or praying for your own breath" do
    post = breath(prayer_status: :prayer_pending)
    comment(post, @author)
    Like.create!(user: @author, likeable: post, reaction_type: :amen)
    PrayerIntercession.create!(user: @author, post: post)
    assert_equal({ "breath" => 1 }, kinds(@author))
  end

  test "a reaction pays the author 1, capped at 50 a day" do
    post = breath
    52.times { |i| Like.create!(user: create_member("seed_fan#{i}"), likeable: post, reaction_type: :amen) }
    assert_equal 50, kinds(@author)["reaction_received"]
  end

  test "a reaction to a comment pays the commenter" do
    c = comment(breath)
    Like.create!(user: @author, likeable: c, reaction_type: :love)
    assert_equal 1, kinds(@reader)["reaction_received"]
  end

  test "un-reacting takes the seed back" do
    like = Like.create!(user: @reader, likeable: breath, reaction_type: :amen)
    assert_equal 11, total(@author)
    like.destroy!
    assert_equal 10, total(@author)
  end

  test "interceding pays 3, capped at 10 a day, only on prayers" do
    12.times { PrayerIntercession.create!(user: @reader, post: breath(prayer_status: :prayer_pending)) }
    PrayerIntercession.create!(user: @reader, post: breath) # not a prayer
    assert_equal 10, kinds(@reader)["intercession"]
    assert_equal 30, total(@reader)
  end

  test "leaving the prayer chain takes the seeds back" do
    i = PrayerIntercession.create!(user: @reader, post: breath(prayer_status: :prayer_pending))
    assert_equal 3, total(@reader)
    i.destroy!
    assert_equal 0, total(@reader)
  end

  test "streak bonuses on days 7, 30 and 100, once per streak day" do
    @author.update_columns(current_breath_streak: 6, streak_updated_on: Date.yesterday)
    breath
    breath # second breath the same day: no second bonus
    assert_equal 1, kinds(@author)["streak_7"]
    assert_equal 20 + 20, total(@author)

    @author.update_columns(current_breath_streak: 29, streak_updated_on: Date.yesterday)
    breath
    assert_equal 1, kinds(@author)["streak_30"]

    @author.update_columns(current_breath_streak: 99, streak_updated_on: Date.yesterday)
    breath # the 4th breath today earns no breath seeds, but the streak still pays
    assert_equal 1, kinds(@author)["streak_100"]
    assert_equal 3, kinds(@author)["breath"]
  end

  test "earning a badge pays 25" do
    breath
    UserBadge.check!(@author)
    assert_equal 1, kinds(@author)["badge"]
    assert_equal 35, total(@author)
  end

  # ── Blocks and uniqueness ─────────────────────────────────────

  test "nothing is earned between people where one blocked the other" do
    post = breath
    MessageBlock.create!(blocker: @author, blocked: @reader)
    Like.create!(user: @reader, likeable: post, reaction_type: :amen)
    comment(post)
    assert_nil kinds(@author)["reaction_received"]
    assert_nil kinds(@author)["comment_received"]
    assert_equal 0, total(@reader)
  end

  test "the same action never pays twice" do
    post = breath
    c = comment(post)
    3.times do
      Seeds.comment_created(c)
      Seeds.breath_published(post)
    end
    assert_equal 1, SeedEvent.where(user: @reader, kind: "comment").count
    assert_equal 1, SeedEvent.where(user: @author, kind: "breath").count
    assert_raises(ActiveRecord::RecordNotUnique) do
      SeedEvent.create!(user: @reader, kind: "comment", points: 5, source: c, created_on: Date.current, created_at: Time.current)
    end
  end

  # ── Reversals ─────────────────────────────────────────────────

  test "deleting a breath takes back what it earned its author, not what others earned" do
    post = breath
    comment(post)
    Like.create!(user: @reader, likeable: post, reaction_type: :amen)
    assert_equal 13, total(@author)

    post.destroy!
    assert_equal 0, total(@author)
    assert_equal 5, total(@reader)
  end

  test "a breath held or blocked by moderation loses its seeds; approval pays again" do
    post = breath
    Like.create!(user: @reader, likeable: post, reaction_type: :amen)
    post.apply_moderation_decision!(:hold)
    assert_equal 0, total(@author)

    post.apply_moderation_decision!(:allow)
    assert_equal 10, total(@author)

    post.apply_moderation_decision!(:block)
    assert_equal 0, total(@author)
  end

  test "deleting a comment takes back the commenter's and the author's seeds" do
    post = breath
    c = comment(post)
    Like.create!(user: @author, likeable: c, reaction_type: :amen)
    assert_equal 6, total(@reader)

    c.soft_delete!
    assert_equal 0, total(@reader)
    assert_equal 10, total(@author)
  end

  test "a comment held or blocked later loses its seeds" do
    c = comment(breath)
    c.update!(moderation_status: :blocked)
    assert_equal 0, total(@reader)
    assert_equal 10, total(@author)

    c.update!(moderation_status: :approved)
    assert_equal 5, total(@reader)
  end

  test "a comment held at creation earns nothing" do
    post = breath
    post.comments.create!(user: @reader, content: LONG, moderation_status: :pending_review)
    assert_equal 0, total(@reader)
    assert_equal 10, total(@author)
  end

  test "anonymous breaths still earn for the author, marked off the public board" do
    post = breath(anonymous: true)
    comment(post)
    assert_equal 12, total(@author)
    assert @author.seed_events.all?(&:anonymous?)
    assert_not @reader.seed_events.first.anonymous?
  end

  # ── Ranks ─────────────────────────────────────────────────────

  test "rank thresholds" do
    expected = { 0 => "Seedling", 49 => "Seedling", 50 => "Sprout", 150 => "Sapling", 400 => "Branch",
                 1_000 => "Fruitful", 2_500 => "Oak", 5_999 => "Oak", 6_000 => "Cedar of Lebanon", 99_999 => "Cedar of Lebanon" }
    expected.each { |seeds, name| assert_equal name, Seeds::Rank.for(seeds).name, "#{seeds} seeds" }
    assert_equal 50, Seeds::Rank.for(100).progress(100)
    assert_equal 50, Seeds::Rank.for(100).seeds_to_next(100)
    assert_equal "an Oak", Seeds::Rank.for(2_500).a_name
  end

  test "reaching a rank notifies once and leaves the celebration pending" do
    @author.update_columns(seeds_total: 45)
    SeedEvent.create!(user: @author, kind: "badge", points: 45, source: @author, created_on: Date.current, created_at: Time.current)
    breath
    @author.reload
    assert_equal 1, @author.seeds_rank_reached
    assert @author.rank_up_pending?
    note = Notification.rank_up.find_by(user: @author)
    assert note
    assert_equal "You're now a Sprout. Keep encouraging the brethren.", note.web_message

    breath
    assert_equal 1, Notification.rank_up.where(user: @author).count
  end

  # ── Safety ────────────────────────────────────────────────────

  test "an award failure never raises" do
    post = breath
    SeedEvent.stub(:create!, ->(*) { raise ActiveRecord::StatementInvalid, "boom" }) do
      assert_nothing_raised { comment(post) }
      assert_nil Seeds.comment_created(post.comments.last)
    end
  end
end

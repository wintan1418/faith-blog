# frozen_string_literal: true

require "test_helper"
require "rake"

# bin/rails seeds:backfill — fair starting totals from history, same caps, safe to re-run.
class SeedsBackfillTest < ActiveSupport::TestCase
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @author = create_member("bf_author")
    @reader = create_member("bf_reader")
    @room = Room.create!(name: "Backfill Room", description: "x", is_public: true)
  end

  # History from before Seeds: build it, then wipe what the live hooks paid.
  def history
    day = 10.days.ago.change(hour: 12)
    posts = Array.new(5) do |i|
      Post.create!(user: @author, room: @room, title: "Old breath #{i}", content: "Body", status: :published,
                   moderation_status: :approved, published_at: day + i.minutes, created_at: day + i.minutes)
    end
    25.times do |i|
      posts[i % 5].comments.create!(user: @reader, content: "A thoughtful old comment number #{i}",
                                    moderation_status: :approved, created_at: day + 1.hour + i.minutes)
    end
    Like.create!(user: @reader, likeable: posts.first, reaction_type: :amen, created_at: day + 2.hours)
    # A week-long streak, ending yesterday.
    (1..7).each do |n|
      at = (8 - n).days.ago.change(hour: 9)
      Post.create!(user: @reader, room: @room, title: "Streak #{n}", content: "Body", status: :published,
                   moderation_status: :approved, published_at: at, created_at: at)
    end
    SeedEvent.delete_all
    SeedRankUp.delete_all
    Notification.rank_up.delete_all
    User.update_all(seeds_total: 0, seeds_rank_reached: 0, seeds_rank_seen: 0)
  end

  test "backfill pays history within the daily caps, and a second run pays nothing" do
    history
    added = Seeds::Backfill.new(io: nil).run
    assert added.positive?

    assert_equal 3, SeedEvent.where(user: @author, kind: "breath").count # 5 breaths in one day, cap 3
    assert_equal 20, SeedEvent.where(user: @reader, kind: "comment").count # 25 comments in one day, cap 20
    assert_equal 5, SeedEvent.where(user: @author, kind: "comment_received").count # once per commenter per breath
    assert_equal 1, SeedEvent.where(user: @reader, kind: "streak_7").count
    assert_equal 1, SeedEvent.where(user: @author, kind: "reaction_received").count
    assert_equal SeedEvent.where(user: @reader).sum(:points), @reader.reload.seeds_total

    totals = User.order(:id).pluck(:seeds_total)
    assert_equal 0, Seeds::Backfill.new(io: nil).run
    assert_equal totals, User.order(:id).pluck(:seeds_total)
  end

  test "backfill sends no notifications or celebrations" do
    history
    Seeds::Backfill.new(io: nil).run
    @reader.reload
    assert @reader.seeds_total >= 150
    assert_not @reader.rank_up_pending?
    assert_equal @reader.seeds_rank.index, @reader.seeds_rank_reached
    assert_equal 0, Notification.rank_up.count
  end

  test "the rake task runs" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("seeds:backfill")
    assert_output(/\[seeds:backfill\] Done/) { Rake::Task["seeds:backfill"].execute }
  end
end

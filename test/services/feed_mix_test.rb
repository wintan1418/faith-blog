# frozen_string_literal: true

require "test_helper"

class FeedMixTest < ActiveSupport::TestCase
  def entry(id, author, minutes_ago, kind: :post)
    { kind: kind, id: id, at: Time.zone.parse("2026-11-22 12:00") - minutes_ago.minutes, author_id: author }
  end

  def longest_run(entries)
    entries.chunk_while { |a, b| a[:author_id] == b[:author_id] }.map(&:size).max
  end

  test "a burst from one author is spread out: never more than 2 in a row while others are left" do
    burst  = (1..50).map { |i| entry(i, :wintan, i) }            # 50 in the last hour
    others = (1..30).map { |i| entry(100 + i, "m#{i % 6}", 60 + i * 20) }
    mixed = FeedMix.call(burst + others, seed: "7:2026-11-22")

    assert_equal (burst + others).map { |e| e[:id] }.sort, mixed.map { |e| e[:id] }.sort, "nothing lost or doubled"
    first_with_others = mixed.first(40)
    assert_operator longest_run(first_with_others), :<=, 2
    first_with_others.each_cons(10) do |window|
      assert_operator window.count { |e| e[:author_id] == :wintan }, :<=, 3
    end
  end

  test "when only one author is left, their posts still all appear" do
    mixed = FeedMix.call((1..5).map { |i| entry(i, :solo, i) }, seed: "x")
    assert_equal 5, mixed.size
  end

  test "the same seed gives the same order; still broadly newest first" do
    entries = (1..40).map { |i| entry(i, "a#{i % 7}", i * 30) }
    one = FeedMix.call(entries, seed: "3:2026-11-22")
    assert_equal one, FeedMix.call(entries.shuffle, seed: "3:2026-11-22")
    # The light shuffle moves a card by less than an hour's worth of posts here.
    one.each_with_index { |e, i| assert_operator (e[:id] - (i + 1)).abs, :<=, 3 }
  end

  test "posts since the last visit come before older ones" do
    entries = (1..6).map { |i| entry(i, "a#{i}", i * 10) }
    mixed = FeedMix.call(entries, seed: "s", fresh_after: entries[2][:at] - 1)
    assert_equal [ 1, 2, 3 ], mixed.first(3).map { |e| e[:id] }.sort
  end

  test "keep_order keeps a ranked list but still breaks long runs" do
    ranked = [ entry(1, :a, 5), entry(2, :a, 1), entry(3, :a, 9), entry(4, :b, 2) ]
    assert_equal [ 1, 2, 4, 3 ], FeedMix.call(ranked, seed: "s", keep_order: true).map { |e| e[:id] }
  end
end

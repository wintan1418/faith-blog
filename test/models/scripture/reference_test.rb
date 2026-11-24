# frozen_string_literal: true

require "test_helper"

class Scripture::ReferenceTest < ActiveSupport::TestCase
  R = Scripture::Reference

  # Real Search Console queries that already reach Brethreign.
  test "search queries parse to one canonical slug" do
    {
      "psalm 101:3" => "psalm-101-3",
      "genesis 1 11-12" => "genesis-1-11-12",
      "genesis 1:11-12" => "genesis-1-11-12",
      "2 timothy 3:2-5" => "2-timothy-3-2-5",
      "isaiah 14:13-14" => "isaiah-14-13-14",
      "ephesians chapter 1 verse 3" => "ephesians-1-3",
      "Ps. 23" => "psalm-23",
      "1 Cor 13:4–7" => "1-corinthians-13-4-7",
      "I John 1:9" => "1-john-1-9",
      "Song of Songs 2:1" => "song-of-solomon-2-1",
      "Jude 3" => "jude-1-3",
      "John 3:16-16" => "john-3-16"
    }.each { |query, slug| assert_equal slug, R.parse(query)&.slug, query }
  end

  test "slug spellings resolve to the same reference" do
    {
      "genesis-1-11-to-12" => "genesis-1-11-12",
      "psalms-23" => "psalm-23",
      "1-cor-13-4-7" => "1-corinthians-13-4-7",
      "ephesians-chapter-1-verse-3" => "ephesians-1-3",
      "first-john-4-19" => "1-john-4-19",
      "psalm-101-3" => "psalm-101-3"
    }.each { |slug, canonical| assert_equal canonical, R.from_slug(slug)&.slug, slug }
  end

  test "references that don't exist are nil" do
    assert_nil R.parse("Genesis 51")
    assert_nil R.parse("Psalm 23:7")
    assert_nil R.from_slug("not-a-verse")
    assert_nil R.from_slug("genesis")
    assert_nil R.from_slug("lookup")
  end

  test "labels and ranges" do
    ref = R.parse("Genesis 1:11-12")
    assert_equal "Genesis 1:11–12", ref.to_s
    assert_equal "Genesis 1:11-12", ref.plain
    assert_equal 11..12, ref.verses
    assert ref.range?
    assert_equal 6, R.parse("Psalm 23").verse_count
  end

  test "previous and next cross chapter and book lines" do
    assert_equal "Matthew 1:1", R.parse("Malachi 4:6").next.to_s
    assert_equal "Job 42", R.parse("Psalm 1").previous.to_s
    assert_equal "Genesis 1:31", R.parse("Genesis 2:1").previous.to_s
    assert_nil R.parse("Genesis 1:1").previous
    assert_nil R.parse("Revelation 22").next
    assert_equal "Psalm 101:4", R.parse("Psalm 101:3").next.to_s
  end

  test "scan finds references in writing, but not ordinary words" do
    found = R.scan("On John 3:16 tonight. Psalm 23 and 1 Cor. 13:4-7, Mark 2 people, Psalms 119:105.").map { |r, *, text| [ r.to_s, text ] }
    assert_equal [ [ "John 3:16", "John 3:16" ], [ "Psalm 23", "Psalm 23" ],
                   [ "1 Corinthians 13:4–7", "1 Cor. 13:4-7" ], [ "Psalm 119:105", "Psalms 119:105" ] ], found
    assert_empty R.scan("Job 2 starts Monday; I read Acts 2 people")
  end

  test "the canon is complete" do
    assert_equal 66, Scripture::Canon::BOOKS.size
    assert_equal 1_189, Scripture::Canon.chapter_count
    assert_equal 31_102, Scripture::Canon::BOOKS.sum { |b| b.verse_counts.sum }
  end

  test "every curated popular verse is a real reference, listed once" do
    raw = YAML.load_file(Scripture::Catalog::POPULAR_FILE)
    assert_operator raw.size, :>=, 500
    raw.each { |text| assert R.parse(text), "#{text} should parse" }
    assert_equal raw.size, Scripture::Catalog.popular.size, "duplicates in popular_verses.yml"
    %w[psalm-101-3 genesis-1-11-12 2-timothy-3-2-5 isaiah-14-13-14 ephesians-1-3].each do |slug|
      assert_includes Scripture::Catalog.popular_slugs, slug
    end
  end
end

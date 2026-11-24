# frozen_string_literal: true

require "test_helper"

# Series: a writer's multi-part breaths. Only the author's own signed breaths
# join; readers only see the parts fit for a public page; parts keep an order
# the author can change.
class SeriesTest < ActiveSupport::TestCase
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @writer = create_member("series_writer")
    @other = create_member("series_other")
    @series = @writer.series.create!(title: "The Gospel and Material Prosperity")
  end

  teardown { ENV.delete("AI_MODERATION_STUB") }

  def breath(user, title, **attrs)
    Post.create!({ user: user, title: title, content: "Words for #{title}.", status: :published,
                   moderation_status: :approved }.merge(attrs))
  end

  test "title markers: brackets, hashes, Part, Day, roman numerals, subtitles and Unicode bold" do
    {
      "The Gospel and Material Prosperity (Part 2)" => [ "the gospel and material prosperity", 2 ],
      "THE INHERITANCE (#2)" => [ "the inheritance", 2 ],
      "The Whole Man. Day 1." => [ "the whole man", 1 ],
      "Faith vs Tradition (5)" => [ "faith vs tradition", 5 ],
      "𝗪𝗵𝗼 𝗜𝘀 𝗮 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿? (𝟭)" => [ "who is a teenager", 1 ],
      "Who Is a Teenager? (2) Two Boys and a Foundation" => [ "who is a teenager", 2 ],
      "The Redemption of the Brain, Part 4 When Understanding Returns" => [ "the redemption of the brain", 4 ],
      "God in the work space (1). The Intellectual Bluff" => [ "god in the work space", 1 ],
      "Magdalene Part II" => [ "magdalene", 2 ],
      "Faith and the Algorithm #3" => [ "faith and the algorithm", 3 ],
      "𝗦𝗮𝗻𝗰𝘁𝗶𝗳𝗶𝗲𝗱 𝗘𝗻𝗼𝘂𝗴𝗵 𝘁𝗼 𝗕𝗲 𝗟𝗼𝘃𝗲𝗱 (𝟲)" => [ "sanctified enough to be loved", 6 ]
    }.each do |title, (key, part)|
      parsed = SeriesTitle.parse(title)
      assert parsed, "expected a part marker in #{title.inspect}"
      assert_equal key, parsed.key, title
      assert_equal part, parsed.part, title
    end
  end

  test "titles without a part marker are left alone" do
    [ "Psalm 23", "Top 10 lessons", "Romans 12:2 and me", "Partner 3", "Today 5 things",
      "The whole man: Sleep, an evidence of trust", "Sanctified Enough to Be Loved : The Problem Is Usually in the Room",
      nil, "" ].each do |title|
      assert_nil SeriesTitle.parse(title), title.inspect
    end
  end

  test "a marker with no words before it gives a number but nothing to group by" do
    parsed = SeriesTitle.parse("(2/7) The Friend That Offends")
    assert_equal 2, parsed.part
    assert_nil parsed.key
    assert_nil SeriesTitle.parse("Day 1 of my journey").key
  end

  test "an untitled breath goes by the first line of its words" do
    post = Post.new(content: "Faith vs Tradition (4)<br><br>Today we look at the elders.")
    assert_equal "Faith vs Tradition (4)", SeriesTitle.effective_title(post)
    assert_equal "Faith vs Tradition (4)", SeriesTitle.effective_title(Post.new(title: "Faith vs Tradition (4)", content: "x"))
  end

  test "a breath joins at the end and the author can reorder and remove parts" do
    one = breath(@writer, "Part one", series: @series)
    two = breath(@writer, "Part two", series: @series)
    three = breath(@writer, "Part three", series: @series)
    assert_equal [ 1, 2, 3 ], [ one, two, three ].map { |p| p.reload.series_position }

    assert @series.move!(three, -1)
    assert_equal [ one, three, two ].map(&:id), @series.posts.reload.map(&:id)
    assert_equal [ 1, 2, 3 ], @series.posts.map(&:series_position)
    assert_not @series.move!(one, -1), "already first"

    three.update!(series: nil)
    assert_nil three.reload.series_position
    assert_equal [ 1, 3 ], @series.posts.reload.map(&:series_position), "the others keep their numbers"
  end

  test "part numbers are the writer's own: a part never posted stays a gap" do
    teen = @writer.series.create!(title: "Who Is a Teenager?")
    parts = [ "𝗪𝗵𝗼 𝗜𝘀 𝗮 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿? (𝟭)", "Who Is a Teenager? (2) Two Boys", "Who Is a Teenager? (4)" ].map do |title|
      breath(@writer, title, series: teen)
    end
    assert_equal [ 1, 2, 4 ], parts.map { |p| p.reload.series_position }, "part 3 was never posted"

    six = breath(@writer, "𝗪𝗵𝗼 𝗜𝘀 𝗮 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿? (𝟲)", series: teen)
    assert_equal 6, six.reload.series_position, "a later number in the title is kept"

    teen.number_parts!(teen.posts.to_a)
    assert_equal [ 1, 2, 4, 6 ], teen.posts.reload.map(&:series_position)

    # A late part fills its own gap, even when posted after a later one.
    five = breath(@writer, "Who Is a Teenager? (5)", series: teen)
    assert_equal 5, five.reload.series_position
    assert_equal [ 1, 2, 4, 5, 6 ], teen.posts.reload.map(&:series_position)
    five.update!(series: nil)

    # Swapping neighbours swaps their numbers; the gap stays put.
    assert teen.move!(six, -1)
    assert_equal [ 1, 2, 4, 6 ], teen.posts.reload.map(&:series_position)
    assert_equal six.id, teen.posts.third.id
  end

  test "only the author's own series, and never an anonymous breath" do
    post = Post.new(user: @other, title: "Not mine", content: "x", status: :published, series: @series)
    assert_not post.valid?
    assert_includes post.errors[:series], "must be one of your own"

    anon = Post.new(user: @writer, title: "Hidden", content: "x", status: :published, anonymous: true, series: @series)
    assert_not anon.valid?
    assert_match(/anonymous/i, anon.errors.full_messages.to_sentence)
  end

  test "readers see only public parts; the author sees every part" do
    private_room = Room.create!(name: "Series Private Room", description: "x", is_public: false)
    shown = breath(@writer, "Shown", series: @series)
    breath(@writer, "Prayer part", series: @series, prayer_status: :prayer_pending)
    breath(@writer, "Draft part", series: @series, status: :draft)
    breath(@writer, "Room part", series: @series, room: private_room)
    breath(@writer, "Held part", series: @series, moderation_status: :pending_review)

    assert_equal [ shown ], @series.parts_for(nil)
    assert_equal [ shown ], @series.parts_for(@other)
    assert_equal 5, @series.parts_for(@writer).size
    assert @series.readable_by?(nil)
  end

  test "a series with nothing public, or by a private profile, isn't readable by others" do
    breath(@writer, "Draft only", series: @series, status: :draft)
    assert_not @series.readable_by?(nil)
    assert @series.readable_by?(@writer)

    breath(@writer, "Live now", series: @series)
    assert @series.readable_by?(@other)
    @writer.profile&.update!(public_profile: false) || @writer.create_profile!(public_profile: false)
    assert_not @series.reload.readable_by?(@other)
    assert_not Series.publicly_listed.exists?(@series.id)
  end

  test "slugs come from plain text, stay put on rename, and titles are unique per author" do
    bold = @writer.series.create!(title: "𝗪𝗵𝗼 𝗜𝘀 𝗮 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿?")
    assert_equal "who-is-a-teenager", bold.slug
    bold.update!(title: "Who is a teenager, really?")
    assert_equal "who-is-a-teenager", bold.reload.slug

    dupe = @writer.series.build(title: "the gospel and material prosperity!")
    assert_not dupe.valid?
    assert @other.series.build(title: "The Gospel and Material Prosperity").valid?
  end

  test "deleting a series keeps its breaths" do
    part = breath(@writer, "Stays", series: @series)
    @series.destroy
    part.reload
    assert_nil part.series_id
    assert_nil part.series_position
  end
end

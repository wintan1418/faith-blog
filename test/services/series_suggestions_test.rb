# frozen_string_literal: true

require "test_helper"
require "rake"

# Finding series from titles (the composer hint and `rake series:suggest`)
# and the hand-checked mapping file.
class SeriesSuggestionsTest < ActiveSupport::TestCase
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @writer = create_member("suggest_writer")
    @other = create_member("suggest_other")
  end

  teardown { ENV.delete("AI_MODERATION_STUB") }

  def breath(user, title, content: nil, **attrs)
    Post.create!({ user: user, title: title, content: content || "Words for #{title}.", status: :published,
                   moderation_status: :approved }.merge(attrs))
  end

  test "the next part of an earlier title suggests a new series with the earlier parts" do
    one = breath(@writer, "𝗪𝗵𝗼 𝗜𝘀 𝗮 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿? (𝟭)")
    two = breath(@writer, "Who Is a Teenager? (2) Two Boys and a Foundation")
    breath(@other, "Who Is a Teenager? (3)")

    suggestion = SeriesSuggestions.for_title(@writer, "Who is a teenager? (3)")
    assert_nil suggestion.series
    assert_equal "Who is a teenager?", suggestion.title
    assert_equal 3, suggestion.part
    assert_equal [ two.id, one.id ], suggestion.post_ids, "only the writer's own breaths"

    assert_nil SeriesSuggestions.for_title(@writer, "Something new (1)")
    assert_nil SeriesSuggestions.for_title(@writer, "Psalm 23")
  end

  test "an existing series is suggested by name" do
    series = @writer.series.create!(title: "The Gospel and Material Prosperity")
    breath(@writer, "The Gospel and Material Prosperity (Part 1)", series: series)

    suggestion = SeriesSuggestions.for_title(@writer, "The Gospel and Material Prosperity (Part 2)")
    assert_equal series, suggestion.series
    assert_empty suggestion.post_ids
  end

  test "groups: same author and base title, untitled breaths by their first line, anonymous left out" do
    breath(@writer, "Faith vs Tradition (1)")
    breath(@writer, "Faith vs Tradition (2)")
    untitled = breath(@writer, nil, content: "Faith vs Tradition (4)<br><br>On the elders.")
    breath(@writer, "Faith vs Tradition (5)", anonymous: true)
    breath(@other, "Faith vs Tradition (3)")
    breath(@writer, "THE INHERITANCE (#1)")

    groups = SeriesSuggestions.groups(Post.where(user: [ @writer, @other ]), singles: true)
    faith = groups.find { |g| g.user == @writer && g.key == "faith vs tradition" }
    assert_equal [ 1, 2, 4 ], faith.parts
    assert_includes faith.posts, untitled
    assert_equal "Faith vs Tradition", faith.title
    assert groups.any? { |g| g.user == @other && g.posts.size == 1 }
    assert groups.any? { |g| g.key == "the inheritance" && g.posts.size == 1 }
    assert_equal 1, SeriesSuggestions.groups(Post.where(user: @writer)).size, "singles left out by default"
  end

  test "the mapping file: explicit parts and numbers, left-out posts and report-only entries" do
    parts = [ breath(@writer, "Sanctified Enough to Be Loved : The Problem Is Usually in the Room"),
              breath(@writer, "(2/7) The Friend That Offends"),
              breath(@writer, "Sanctified Enough to Be Loved (6)") ]
    dupe = breath(@writer, "Sanctified Enough to Be Loved (6)")
    stranger = breath(@other, "Not theirs")
    lone = breath(@writer, "Only one (1)")
    file = Tempfile.new([ "series", ".yml" ])
    file.write(<<~YAML)
      - author: #{@writer.username.upcase}
        title: Sanctified Enough to Be Loved
        parts: { #{parts[0].id}: 1, #{parts[1].id}: 2, #{parts[2].id}: 6, #{stranger.id}: 7 }
        exclude: { #{dupe.id}: "duplicate" }
      - author: #{@writer.username}
        title: Only one
        parts: [ #{lone.id} ]
        create: false
    YAML
    file.close

    sanctified, single = SeriesMapping.load(file.path)
    report = sanctified.report_lines.join("\n")
    assert_match(/new series, 4 parts, missing part 3, 4, 5/, report)
    assert_match(/Part 7 .*skipped: by @#{@other.username}/, report)
    assert_match(/left out ##{dupe.id} +duplicate/, report)
    assert_equal [ parts[0].id, parts[1].id, parts[2].id, stranger.id, dupe.id ], sanctified.post_ids

    assert_no_difference -> { Series.count } do
      assert_equal [ false, 0 ], single.apply!
    end
    assert_equal [ true, 3 ], sanctified.apply!
    series = @writer.series.find_by!(title: "Sanctified Enough to Be Loved")
    assert_equal [ [ parts[0].id, 1 ], [ parts[1].id, 2 ], [ parts[2].id, 6 ] ], series.posts.pluck(:id, :series_position)
    assert_nil dupe.reload.series_id
    assert_nil stranger.reload.series_id
    assert_equal "Sanctified Enough to Be Loved : The Problem Is Usually in the Room", parts[0].reload.title, "titles untouched"

    # Applying again changes nothing.
    assert_equal [ false, 3 ], SeriesMapping.load(file.path).first.apply!
    assert_equal 1, @writer.series.count
  ensure
    file&.unlink
  end

  test "rake series:suggest is a dry run unless APPLY=1" do
    breath(@writer, "Magdalene (1)")
    breath(@writer, "Magdalene (2)")
    Rails.application.load_tasks unless Rake::Task.task_defined?("series:suggest")
    task = Rake::Task["series:suggest"]

    out, = capture_io do
      with_env("MAPPING" => "none", "AUTHOR" => @writer.username) { task.reenable; task.invoke }
    end
    assert_match(/DRY RUN/, out)
    assert_match(/"Magdalene" \(new series, 2 parts\)/, out)
    assert_equal 0, @writer.series.count

    capture_io do
      with_env("MAPPING" => "none", "AUTHOR" => @writer.username, "APPLY" => "1") { task.reenable; task.invoke }
    end
    assert_equal [ "Magdalene" ], @writer.series.pluck(:title)
    assert_equal [ 1, 2 ], @writer.series.first.posts.pluck(:series_position)
  end

  private

  def with_env(vars)
    old = vars.keys.to_h { |k| [ k, ENV[k] ] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| ENV[k] = v }
  end
end

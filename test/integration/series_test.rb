# frozen_string_literal: true

require "test_helper"

# Series end to end: filing a breath from the composer and the edit page, the
# post page's series card, the feed's "Part 2 of 3", /series/:slug with the
# author's reorder / remove tools, the profile's Series row and the sitemap.
class SeriesFlowTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @writer = create_member("series_flow_writer", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i)
    @reader = create_member("series_flow_reader", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i)
    @series = @writer.series.create!(title: "The Gospel and Material Prosperity")
  end

  teardown { ENV.delete("AI_MODERATION_STUB") }

  def breath(title, user: @writer, **attrs)
    Post.create!({ user: user, title: title, content: "Words for #{title}.", status: :published,
                   moderation_status: :approved }.merge(attrs))
  end

  def publish_params(title, **post)
    { post: { title: title, content: "Body of #{title}.", kind: "breath", prayer_status: "not_a_prayer",
              status: "published" }.merge(post) }
  end

  test "the composer offers my series and starts a new one by name" do
    sign_in @writer
    get new_post_path
    assert_select "select[name='post[series_id]']" do
      assert_select "option[value='']", text: "No series"
      assert_select "option[value=?]", @series.id.to_s, text: @series.title
      assert_select "option[value=new]"
    end
    assert_select "input[name='post[new_series_title]']"
    assert_select "form[data-controller~=series-picker] input[name='post[title]'][data-action~='input->series-picker#titleChanged']"
    assert_select "select[name='post[room_id]']" # the room picker is still there

    post posts_path, params: publish_params("Who Is a Teenager? (1)", series_id: "new", new_series_title: "Who Is a Teenager?")
    created = @writer.posts.order(:id).last
    assert_equal "Who Is a Teenager?", created.series.title
    assert_equal 1, created.series_position
  end

  test "a new part joins an existing series at the end, or at the number in its title" do
    breath("Part 1", series: @series)
    sign_in @writer
    post posts_path, params: publish_params("The Gospel and Material Prosperity (Part 3)", series_id: @series.id)
    third = @writer.posts.order(:id).last
    assert_equal @series, third.series
    assert_equal 3, third.series_position, "part 2 isn't posted yet: a gap"
  end

  test "accepting the hint brings the earlier parts along, in order" do
    one = breath("THE INHERITANCE (#1)")
    two = breath("THE INHERITANCE (#2)")
    sign_in @writer

    get series_suggestion_posts_path, params: { title: "The Inheritance (#3)" }, as: :json
    hint = response.parsed_body["suggestion"]
    assert_equal "The Inheritance", hint["title"]
    assert_equal 3, hint["part"]
    assert_equal [ two.id, one.id ].sort, hint["post_ids"].sort

    post posts_path, params: publish_params("THE INHERITANCE (#3)", series_id: "new", new_series_title: "THE INHERITANCE",
                                            series_adopt_post_ids: hint["post_ids"].join(","))
    series = @writer.series.find_by!(title: "THE INHERITANCE")
    assert_equal [ one.id, two.id, @writer.posts.order(:id).last.id ], series.posts.pluck(:id)
    assert_equal [ 1, 2, 3 ], series.posts.pluck(:series_position)
  end

  test "nobody files a breath in someone else's series, or someone else's breath in theirs" do
    theirs = breath("Not yours", user: @reader)
    sign_in @reader
    assert_no_difference -> { Post.count } do
      post posts_path, params: publish_params("Sneaky (2)", series_id: @series.id)
    end
    assert_response :unprocessable_entity
    assert_match "isn&#39;t one of yours", response.body

    post posts_path, params: publish_params("Mine (2)", series_id: "new", new_series_title: "Mine",
                                            series_adopt_post_ids: breath("Writer's own").id.to_s)
    assert_equal [ @reader.posts.order(:id).last.id ], @reader.series.find_by!(title: "Mine").posts.pluck(:id)
    assert_nil theirs.reload.series_id
  end

  test "an anonymous breath can't join a series" do
    sign_in @writer
    assert_no_difference -> { Post.count } do
      post posts_path, params: publish_params("Hidden (2)", series_id: @series.id, anonymous: "1")
    end
    assert_response :unprocessable_entity
  end

  test "the edit page moves a breath into a series and out again; staff edits leave it alone" do
    part = breath("Edit me")
    sign_in @writer
    get edit_post_path(part)
    assert_select "form[action=?] select[name='post[series_id]']", post_path(part)

    patch post_path(part), params: { post: { title: "Edit me", series_id: @series.id } }
    assert_equal @series, part.reload.series
    patch post_path(part), params: { post: { title: "Edit me", series_id: "" } }
    assert_nil part.reload.series_id

    part.update!(series: @series)
    admin = create_member("series_flow_admin", role: :admin)
    sign_in admin
    get edit_post_path(part)
    assert_select "form[action=?] select[name='post[series_id]']", post_path(part), count: 0
    patch post_path(part), params: { post: { title: "Edit me", series_id: "" } }
    assert_equal @series, part.reload.series
  end

  test "the post page shows where the breath sits, with previous, next and every public part" do
    one = breath("Prosperity one", series: @series)
    two = breath("Prosperity two", series: @series)
    three = breath("Prosperity three", series: @series)
    prayer = breath("Prosperity prayer", series: @series, prayer_status: :prayer_pending)

    get post_path(two)
    assert_select ".sr-topline", text: /Part 2 of 3/
    assert_select ".sr-card" do
      assert_select ".sr-kicker", text: /Part 2 of 3/
      assert_select "a[href=?]", series_path(@series), text: @series.title
      assert_select "a.sr-step.is-prev[href=?]", post_path(one)
      assert_select "a.sr-step.is-next[href=?]", post_path(three)
      assert_select "details.sr-parts[data-controller=details-wide] li", count: 3
      assert_select "a[href=?]", post_path(prayer), count: 0
    end

    sign_in @writer
    get post_path(two)
    assert_select "details.sr-parts li", count: 4
    assert_select ".sr-only-you", text: /Prayer request/
  end

  test "a breath that isn't public gets no series card for readers" do
    breath("Public one", series: @series)
    room = Room.create!(name: "Series Hidden Room", description: "x", is_public: false)
    hidden = breath("Room part", series: @series, room: room)
    get post_path(hidden)
    assert_select ".sr-card", count: 0
  end

  test "feed cards say Part N of M, with the writer's numbering" do
    breath("Prosperity one", series: @series)
    two = breath("Prosperity two", series: @series)
    two.update_columns(series_position: 4)
    breath("Not in a series")
    sign_in @reader
    get feed_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(two)} a.eg-post-flag.is-series[href=?]", series_path(@series), text: "Part 4 of 4"
    assert_select "a.eg-post-flag.is-series", count: 2
  end

  test "the series page lists public parts in order for readers, with title and canonical" do
    one = breath("Prosperity one", series: @series)
    two = breath("Prosperity two", series: @series)
    breath("Prosperity draft", series: @series, status: :draft)
    breath("Prosperity prayer", series: @series, prayer_status: :prayer_pending)

    get series_path(@series)
    assert_response :success
    assert_select "title", text: "The Gospel and Material Prosperity · a series by #{@writer.display_name} - Brethreign"
    assert_select "link[rel=canonical][href=?]", series_url(@series)
    assert_select "h1", text: @series.title
    assert_select "a.sr-byline[href=?]", user_path(@writer.username)
    assert_select "ol.sr-list > li", count: 2
    assert_select "ol.sr-list > li:first-child a[href=?]", post_path(one)
    assert_select "ol.sr-list > li:last-child a[href=?]", post_path(two)
    assert_select ".sr-item-tools", count: 0
    assert_select ".sr-manage", count: 0
    assert_select "script[type='application/ld+json']", text: /CreativeWorkSeries/
  end

  test "a series with nothing public is not found for readers" do
    breath("Only a draft", series: @series, status: :draft)
    get series_path(@series)
    assert_response :not_found

    sign_in @writer
    get series_path(@series)
    assert_response :success
    assert_select ".sr-only-you", text: "Draft"
  end

  test "the author reorders, removes parts, renames and deletes the series" do
    one = breath("Prosperity one", series: @series)
    two = breath("Prosperity two", series: @series)
    three = breath("Prosperity three", series: @series)
    sign_in @writer

    get series_path(@series)
    assert_select ".sr-item-tools", count: 3
    patch move_series_part_path(@series, three, direction: "up")
    assert_redirected_to series_path(@series, anchor: "part-#{three.id}")
    assert_equal [ one.id, three.id, two.id ], @series.posts.reload.pluck(:id)

    delete series_part_path(@series, one)
    assert_nil one.reload.series_id
    assert Post.exists?(one.id), "the breath itself stays"

    patch series_path(@series), params: { series: { title: "Prosperity, Rightly Understood", description: "Three talks." } }
    assert_equal "Prosperity, Rightly Understood", @series.reload.title
    get series_path(@series)
    assert_select ".sr-hero-copy", text: "Three talks."

    delete series_path(@series)
    assert_not Series.exists?(@series.id)
    assert Post.exists?(two.id)
  end

  test "readers can't reorder, remove or edit someone else's series" do
    part = breath("Prosperity one", series: @series)
    breath("Prosperity two", series: @series)
    sign_in @reader

    patch move_series_part_path(@series, part, direction: "down")
    assert_response :not_found
    sign_in @reader # a 404 doesn't keep the test sign-in
    delete series_part_path(@series, part)
    assert_response :not_found
    sign_in @reader
    assert_equal @series, part.reload.series

    patch series_path(@series), params: { series: { title: "Hijacked" } }
    assert_equal "The Gospel and Material Prosperity", @series.reload.title
    delete series_path(@series)
    assert Series.exists?(@series.id)
  end

  test "the profile shows a Series row when the writer has a public one" do
    breath("Prosperity one", series: @series)
    empty = @writer.series.create!(title: "Nothing yet")
    get user_path(@writer.username)
    assert_select ".sr-profile a[href=?]", series_path(@series), text: /The Gospel and Material Prosperity.*1 part/m
    assert_select ".sr-profile a[href=?]", series_path(empty), count: 0

    get user_path(@reader.username)
    assert_select ".sr-profile", count: 0
  end

  test "the sitemap lists public series only" do
    breath("Prosperity one", series: @series)
    hidden = @writer.series.create!(title: "Drafts only")
    breath("Draft", series: hidden, status: :draft)
    get pages_sitemap_path
    assert_includes response.body, series_url(@series)
    assert_not_includes response.body, series_url(hidden)
  end
end

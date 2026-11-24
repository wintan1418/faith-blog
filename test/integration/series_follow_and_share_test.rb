# frozen_string_literal: true

require "test_helper"

# Following a series (and hearing about new parts), automatic grouping with
# Undo, and sharing a series with people who aren't members yet.
class SeriesFollowAndShareTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @writer = create_member("follow_writer", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i)
    @reader = create_member("follow_reader", welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i)
    @series = @writer.series.create!(title: "Who Is a Teenager?")
    breath("𝗪𝗵𝗼 𝗜𝘀 𝗮 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿? (𝟭)", series: @series)
    breath("Who Is a Teenager? (2) Two Boys and a Foundation", series: @series)
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

  def sign_up(username)
    post user_registration_path, params: { user: { username: username, email: "#{username}@example.com",
                                                   password: SecureRandom.base58(16) } }.merge(human_signup_fields)
    User.find_by!(username: username)
  end

  test "follow and unfollow; the series page shows the follower count" do
    sign_in @reader
    get series_path(@series)
    assert_select ".sr-followers", text: "0 followers"
    assert_select "form[action=?] button", series_follow_path(@series), text: /Follow series/

    post series_follow_path(@series)
    assert @series.followed_by?(@reader)
    get series_path(@series)
    assert_select ".sr-followers", text: "1 follower"
    assert_select "button[aria-pressed=true]", text: /Following/

    delete series_follow_path(@series)
    assert_not @series.followed_by?(@reader)
  end

  test "the writer can't follow their own series and sees no button" do
    sign_in @writer
    get series_path(@series)
    assert_select ".sr-follow", count: 0
    post series_follow_path(@series)
    assert_equal 0, @series.series_follows.count
  end

  test "followers hear about a new part once, with the part number" do
    SeriesFollow.create!(user: @reader, series: @series)
    sign_in @writer
    perform_enqueued_jobs(only: SeriesPartAlertJob) do
      post posts_path, params: publish_params("Who Is a Teenager? (3)", series_id: @series.id)
    end
    alert = @reader.notifications.series_new_part.sole
    third = @writer.posts.order(:id).last
    assert_equal third, alert.notifiable
    assert_equal "#{@writer.display_name} added Part 3 to “Who Is a Teenager?”", alert.web_message
    assert_equal Rails.application.routes.url_helpers.post_path(third), alert.target_path

    SeriesPartAlertJob.perform_now(third.id)
    assert_equal 1, @reader.notifications.series_new_part.count, "told once"
    assert_equal 0, @writer.notifications.series_new_part.count
  end

  test "no alert for a part readers can't see" do
    SeriesFollow.create!(user: @reader, series: @series)
    prayer = breath("Who Is a Teenager? prayer", series: @series, prayer_status: :prayer_pending)
    SeriesPartAlertJob.perform_now(prayer.id)
    assert_equal 0, @reader.notifications.series_new_part.count
  end

  test "a signed-out visitor taps Follow, signs up and comes back following" do
    get series_path(@series)
    assert_select ".sr-join h2", text: "Join Brethreign to follow this series"
    post series_follow_path(@series)
    assert_redirected_to new_user_registration_path

    newcomer = sign_up("series_newcomer")
    assert_redirected_to series_path(@series)
    follow_redirect!
    assert_response :success
    assert @series.followed_by?(newcomer)
    assert_select ".sr-follow[aria-pressed=true]"
  end

  test "a shared link credits the sharer as the inviter" do
    get series_path(@series, ref: @reader.username)
    assert_select ".sr-join-credit", text: /#{@reader.display_name} shared this series with you/
    assert_select "link[rel=canonical][href=?]", series_url(@series)
    assert cookies[InviteAttribution::COOKIE.to_s].present?

    friend = sign_up("series_friend")
    assert_equal @reader, friend.invited_by

    get series_path(@series, ref: "nobody_by_that_name")
    assert_select ".sr-join-credit", count: 0
  end

  test "share menu and link previews for the series" do
    sign_in @reader
    get series_path(@series)
    assert_select ".sr-share[data-controller=share][data-share-url-value=?]", series_url(@series, ref: @reader.username)
    assert_select "meta[property='og:title'][content=?]", "Who Is a Teenager? · 2 parts by #{@writer.username}"
    assert_select "meta[property='og:image'][content^='http']"

    get post_path(@writer.posts.order(:id).first)
    assert_select ".sr-card .sr-share[data-controller=share]"
    assert_select ".sr-card .sr-follow"
  end

  test "publishing the next part adds it to the series, with Undo" do
    sign_in @writer
    post posts_path, params: publish_params("𝗪𝗵𝗼 𝗜𝘀 𝗮 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿? (𝟱)")
    fifth = @writer.posts.order(:id).last
    assert_equal @series, fifth.series
    assert_equal 5, fifth.series_position, "the writer's own number"
    assert_equal "𝗪𝗵𝗼 𝗜𝘀 𝗮 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿? (𝟱)", fifth.title, "the title is never rewritten"

    follow_redirect!
    assert_select ".sr-auto", text: /Added to Who Is a Teenager\? as Part 5/
    delete series_part_path(@series, fifth, undo: "added")
    assert_redirected_to post_path(fifth)
    assert_nil fifth.reload.series_id
    assert Series.exists?(@series.id)
  end

  test "the second part of something starts a series with both; Undo takes it back" do
    first = breath("Faith vs Tradition (1)")
    sign_in @writer
    post posts_path, params: publish_params("Faith vs Tradition (2)")
    second = @writer.posts.order(:id).last
    series = second.series
    assert_equal "Faith vs Tradition", series.title
    assert_equal [ [ first.id, 1 ], [ second.id, 2 ] ], series.posts.pluck(:id, :series_position)

    follow_redirect!
    assert_select ".sr-auto", text: /Started the series Faith vs Tradition/
    delete series_part_path(series, second, undo: "created")
    assert_not Series.exists?(series.id)
    assert_nil first.reload.series_id
  end

  test "never across writers, never for anonymous breaths, never over the writer's own choice" do
    breath("Magdalene (1)", user: @reader)
    sign_in @writer
    post posts_path, params: publish_params("Magdalene (2)")
    assert_nil @writer.posts.order(:id).last.series_id

    post posts_path, params: publish_params("Who Is a Teenager? (6)", anonymous: "1")
    assert_nil @writer.posts.order(:id).last.series_id

    other = @writer.series.create!(title: "Something else")
    post posts_path, params: publish_params("Who Is a Teenager? (7)", series_id: other.id)
    assert_equal other, @writer.posts.order(:id).last.series
  end
end

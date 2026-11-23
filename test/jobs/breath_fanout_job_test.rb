# frozen_string_literal: true

require "test_helper"

class BreathFanoutJobTest < ActiveJob::TestCase
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
  end

  def make_user(suffix = SecureRandom.random_number(10**6).to_s.rjust(6, "0"))
    User.create!(
      username: "u_#{suffix}",
      email: "u_#{suffix}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  def make_room
    Room.create!(name: "Room #{SecureRandom.random_number(10**6).to_s.rjust(6, "0")}", description: "x")
  end

  test "publishing a post enqueues the fanout job" do
    user = make_user
    assert_enqueued_with(job: BreathFanoutJob) do
      Post.create!(user: user, room: make_room, title: "A breath worth sharing", content: "Body of the test.", status: :published)
    end
  end

  test "draft posts do not enqueue fanout" do
    user = make_user
    assert_no_enqueued_jobs(only: BreathFanoutJob) do
      Post.create!(user: user, room: make_room, title: "A breath worth sharing", content: "Body of the test.", status: :draft)
    end
  end

  test "fanout creates a breath_from_followee notification for every follower" do
    author = make_user
    follower_a = make_user
    follower_b = make_user
    stranger = make_user

    follower_a.follow(author)
    follower_b.follow(author)

    post = Post.create!(user: author, room: make_room, title: "A breath worth sharing", content: "Body of the test.", status: :published)

    assert_difference -> { Notification.where(notification_type: :breath_from_followee).count }, 2 do
      perform_enqueued_jobs(only: BreathFanoutJob)
    end

    user_ids = Notification.where(notification_type: :breath_from_followee, notifiable: post).pluck(:user_id)
    assert_equal [ follower_a.id, follower_b.id ].sort, user_ids.sort
    refute_includes user_ids, stranger.id
    refute_includes user_ids, author.id
  end

  test "fanout does nothing when author has no followers" do
    user = make_user
    post = Post.create!(user: user, room: make_room, title: "A breath worth sharing", content: "Body of the test.", status: :published)
    assert_nothing_raised { perform_enqueued_jobs(only: BreathFanoutJob) }
    assert_equal 0, Notification.where(notifiable: post).count
  end

  test "fanout inserts in batches and still reaches every follower once" do
    author = make_user
    followers = Array.new(5) { make_user }
    followers.each { |f| f.follow(author) }
    post = Post.create!(user: author, room: make_room, title: "A breath worth sharing", content: "Body of the test.", status: :published)

    inserts = 0
    counter = ->(*, payload) { inserts += 1 if payload[:sql] =~ /\AINSERT INTO "notifications"/ }
    original = BreathFanoutJob::BATCH_SIZE
    silence_warnings { BreathFanoutJob.const_set(:BATCH_SIZE, 2) }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
      BreathFanoutJob.perform_now(post.id)
    end

    assert_equal 3, inserts # 2 + 2 + 1
    user_ids = Notification.where(notification_type: :breath_from_followee, notifiable: post).pluck(:user_id)
    assert_equal followers.map(&:id).sort, user_ids.sort
  ensure
    silence_warnings { BreathFanoutJob.const_set(:BATCH_SIZE, original) } if original
  end
end

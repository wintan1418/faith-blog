# frozen_string_literal: true

require "test_helper"

class BreathFanoutJobTest < ActiveJob::TestCase
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
  end

  def make_user(suffix = SecureRandom.hex(3))
    User.create!(
      username: "u_#{suffix}",
      email: "u_#{suffix}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
  end

  def make_room
    Room.create!(name: "Room #{SecureRandom.hex(3)}", description: "x")
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
end

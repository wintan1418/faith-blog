# frozen_string_literal: true

require "test_helper"

class ScheduledPostPublisherJobTest < ActiveJob::TestCase
  setup do
    @user = User.create!(
      username: "spjt_user",
      email: "spjt@example.com",
      password: "Password!1",
      password_confirmation: "Password!1"
    )
    ENV["AI_MODERATION_STUB"] = "1"
    ENV["AI_MODERATION_PROVIDER"] = nil
  end

  teardown do
    ENV.delete("AI_MODERATION_STUB")
  end

  test "publishes a scheduled post whose time has arrived" do
    post = Post.create!(
      user: @user,
      content: "Praying for the city this morning.",
      kind: :breath,
      status: :scheduled,
      scheduled_for: 1.minute.ago
    )
    assert post.scheduled?

    perform_enqueued_jobs do
      ScheduledPostPublisherJob.new.perform
    end

    post.reload
    assert post.published?
    assert post.moderation_approved?
    assert_not_nil post.published_at
  end

  test "does not publish posts that are not yet due" do
    post = Post.create!(
      user: @user,
      content: "Future thought.",
      kind: :breath,
      status: :scheduled,
      scheduled_for: 1.hour.from_now
    )

    ScheduledPostPublisherJob.new.perform
    post.reload
    assert post.scheduled?
  end

  test "scheduled post with hateful content lands as blocked when published" do
    post = Post.create!(
      user: @user,
      content: "I'm going to bomb that group tonight.",
      kind: :breath,
      status: :scheduled,
      scheduled_for: 1.minute.ago
    )

    perform_enqueued_jobs do
      ScheduledPostPublisherJob.new.perform
    end

    post.reload
    assert post.published?
    assert post.moderation_blocked?, "expected blocked, got #{post.moderation_status}"
  end
end

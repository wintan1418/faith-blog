# frozen_string_literal: true

require "test_helper"

# Trust-based moderation gating: proven authors skip the AI gate entirely,
# but still get a settled review row so the backlog sweep never treats
# their posts as lost jobs.
class TrustedModerationGatingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @room = Room.create!(name: "Trust Room", description: "x")
  end

  teardown { ENV.delete("AI_MODERATION_STUB") }

  def build_user(name)
    User.create!(username: name, email: "#{name}@example.com",
                 password: "password123", password_confirmation: "password123")
  end

  def seed_approved_posts(user, count)
    count.times do |i|
      post = Post.new(user: user, room: @room, title: "Seed #{i}", content: "Body #{i}",
                      status: :published, moderation_status: :approved)
      post.save!(validate: false)
    end
  end

  test "new accounts still go through the AI gate" do
    rookie = build_user("trust_rookie")
    assert_not rookie.trusted_breather?

    assert_enqueued_with(job: AiModerationGateJob) do
      Post.create!(user: rookie, room: @room, title: "First breath", content: "Hello",
                   status: :published, moderation_status: :approved)
    end
  end

  test "proven authors skip the gate and get a settled review row" do
    veteran = build_user("trust_veteran")
    seed_approved_posts(veteran, User::TRUSTED_BREATHER_POSTS)
    assert veteran.trusted_breather?

    post = nil
    assert_no_enqueued_jobs(only: AiModerationGateJob) do
      post = Post.create!(user: veteran, room: @room, title: "Trusted breath", content: "Peace",
                          status: :published, moderation_status: :approved)
    end

    review = post.reload.ai_moderation_review
    assert review.present?, "trusted skip must write a review row for the sweep"
    assert review.cleared?
    assert_equal "trust-gate", review.model
  end

  test "a recent flag revokes trust" do
    veteran = build_user("trust_flagged")
    seed_approved_posts(veteran, User::TRUSTED_BREATHER_POSTS)

    flagged_post = veteran.posts.first
    AiModerationReview.create!(reviewable: flagged_post, user: veteran, status: :flagged,
                               severity: "medium", recommended_action: "require_review",
                               categories: [], reviewed_at: 2.days.ago)

    assert_not veteran.trusted_breather?
  end

  test "elevated risk revokes trust" do
    veteran = build_user("trust_risky")
    seed_approved_posts(veteran, User::TRUSTED_BREATHER_POSTS)
    veteran.risk_profile.update!(risk_level: :watch)

    assert_not veteran.trusted_breather?
  end

  test "staff are always trusted" do
    mod = build_user("trust_mod")
    mod.update_column(:role, User.roles[:moderator]) if User.respond_to?(:roles)
    assert mod.trusted_breather? if mod.moderator?
  end
end

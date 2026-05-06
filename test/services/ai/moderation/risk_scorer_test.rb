# frozen_string_literal: true

require "test_helper"

module Ai
  module Moderation
    class RiskScorerTest < ActiveSupport::TestCase
      def make_user
        User.create!(
          username: "u_#{SecureRandom.hex(4)}",
          email: "u_#{SecureRandom.hex(4)}@example.com",
          password: "password123",
          password_confirmation: "password123"
        )
      end

      def make_room
        Room.create!(name: "Room #{SecureRandom.hex(4)}", description: "x")
      end

      def make_flagged_review_for(user)
        post = Post.create!(
          user: user, room: make_room,
          title: "post #{SecureRandom.hex(2)}",
          content: "x", status: :published
        )
        AiModerationReview.create!(
          reviewable: post,
          user: user,
          status: :flagged,
          severity: "medium",
          recommended_action: "require_review",
          categories: [ "harassment" ],
          score: 0.6,
          summary: "rude",
          model: "stub",
          raw_response: {},
          reviewed_at: Time.current
        )
      end

      test "no flagged reviews keeps user clear" do
        user = make_user
        RiskScorer.call(user: user)
        assert_equal "clear", user.reload.risk_profile.risk_level
        assert_equal 0, user.risk_profile.flagged_reviews_count
      end

      test "one flagged review puts user on watch" do
        user = make_user
        make_flagged_review_for(user)
        RiskScorer.call(user: user)

        profile = user.reload.risk_profile
        assert_equal "watch", profile.risk_level
        assert_equal 1, profile.flagged_reviews_count
      end

      test "three flagged reviews put user on restricted" do
        user = make_user
        3.times { make_flagged_review_for(user) }
        RiskScorer.call(user: user)

        assert_equal "restricted", user.reload.risk_profile.risk_level
        assert_equal 3, user.risk_profile.flagged_reviews_count
      end

      test "scorer never auto-demotes a suspended user" do
        user = make_user
        user.risk_profile.update!(risk_level: :suspended)
        RiskScorer.call(user: user)
        assert_equal "suspended", user.reload.risk_profile.risk_level
      end
    end
  end
end

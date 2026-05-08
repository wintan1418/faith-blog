# frozen_string_literal: true

require "test_helper"

module Ai
  module Moderation
    class PostGatekeeperTest < ActiveSupport::TestCase
      def with_stub_env
        prior_stub = ENV["AI_MODERATION_STUB"]
        prior_provider = ENV["AI_MODERATION_PROVIDER"]
        ENV["AI_MODERATION_STUB"] = "1"
        ENV["AI_MODERATION_PROVIDER"] = nil
        yield
      ensure
        ENV["AI_MODERATION_STUB"] = prior_stub
        ENV["AI_MODERATION_PROVIDER"] = prior_provider
      end

      def author
        @author ||= User.create!(
          username: "gk_author",
          email: "gk_author@example.com",
          password: "Password!1",
          password_confirmation: "Password!1"
        )
      end

      def build_post(body)
        Post.new(
          user: author,
          content: body,
          status: :published,
          kind: :breath
        )
      end

      test "benign content gets :allow" do
        with_stub_env do
          verdict = PostGatekeeper.call(post: build_post("Praying for the city this week."))
          assert verdict.allow?, "expected :allow, got #{verdict.decision} (#{verdict.severity})"
        end
      end

      test "high-severity violence content gets :block" do
        with_stub_env do
          verdict = PostGatekeeper.call(post: build_post("I'm going to bomb that group tonight."))
          assert verdict.block?, "expected :block, got #{verdict.decision}"
          assert_equal "explicit_category", verdict.reason
        end
      end

      test "medium-severity harassment gets :hold" do
        with_stub_env do
          verdict = PostGatekeeper.call(post: build_post("You are stupid and worthless and nobody likes you."))
          assert verdict.hold?, "expected :hold, got #{verdict.decision}"
        end
      end

      test "fail-open returns :allow when AI raises" do
        with_stub_env do
          original = Reviewer.method(:call)
          Reviewer.define_singleton_method(:call) { |**_| raise Client::ApiError, "boom" }
          verdict = PostGatekeeper.call(post: build_post("Anything"))
          assert verdict.allow?
          assert_equal "moderation_unavailable", verdict.reason
          assert_nil verdict.result
        ensure
          Reviewer.define_singleton_method(:call, &original) if original
        end
      end

      test "verdict#persist_review! creates an AiModerationReview" do
        with_stub_env do
          post = build_post("This is gentle reflective content.")
          post.save!
          verdict = PostGatekeeper.call(post: post)
          review = verdict.persist_review!(post)
          assert review.persisted?
          assert_equal post, review.reviewable
        end
      end
    end
  end
end

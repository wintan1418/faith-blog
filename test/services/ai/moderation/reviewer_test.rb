# frozen_string_literal: true

require "test_helper"

module Ai
  module Moderation
    class ReviewerTest < ActiveSupport::TestCase
      def with_stub_env
        original_stub = ENV["AI_MODERATION_STUB"]
        original_key = ENV["ANTHROPIC_API_KEY"]
        ENV["AI_MODERATION_STUB"] = "1"
        ENV["ANTHROPIC_API_KEY"] = nil
        yield
      ensure
        ENV["AI_MODERATION_STUB"] = original_stub
        ENV["ANTHROPIC_API_KEY"] = original_key
      end

      test "returns a safe Result for benign content" do
        with_stub_env do
          result = Reviewer.call(content: "Praying for everyone going through a hard week.")
          assert_kind_of Result, result
          assert result.safe
          assert_equal "none", result.severity
          assert_equal "allow", result.recommended_action
          assert_empty result.categories
        end
      end

      test "flags violence keywords as high severity" do
        with_stub_env do
          result = Reviewer.call(content: "I'm going to bomb that group.")
          refute result.safe
          assert_equal "high", result.severity
          assert_equal "hide_pending_review", result.recommended_action
          assert_includes result.categories, "violence"
        end
      end

      test "flags harassment keywords as medium severity" do
        with_stub_env do
          result = Reviewer.call(content: "You are stupid and worthless.")
          refute result.safe
          assert_equal "medium", result.severity
          assert_equal "require_review", result.recommended_action
        end
      end

      test "Result#flagged? mirrors safe flag" do
        with_stub_env do
          safe = Reviewer.call(content: "All good here")
          flagged = Reviewer.call(content: "scam link click here")
          refute safe.flagged?
          assert flagged.flagged?
        end
      end

      test "raw_response is captured for auditing" do
        with_stub_env do
          result = Reviewer.call(content: "anything")
          assert result.raw_response.is_a?(Hash)
          assert result.raw_response["content"].present?
        end
      end
    end
  end
end

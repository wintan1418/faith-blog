# frozen_string_literal: true

require "test_helper"

module Ai
  module Composer
    class ScriptureSuggesterTest < ActiveSupport::TestCase
      def with_stub_env
        prior = ENV["AI_MODERATION_STUB"]
        ENV["AI_MODERATION_STUB"] = "1"
        yield
      ensure
        ENV["AI_MODERATION_STUB"] = prior
      end

      test "returns themed verses for an anxious draft" do
        with_stub_env do
          draft = "I have been so anxious about the future, my heart won't stop racing about money."
          result = ScriptureSuggester.call(content: draft)
          refute result.empty?
          assert_includes result.verses.map(&:reference), "Philippians 4:6-7"
        end
      end

      test "returns no verses for a too-short draft" do
        with_stub_env do
          result = ScriptureSuggester.call(content: "hi")
          assert result.empty?
        end
      end
    end
  end
end

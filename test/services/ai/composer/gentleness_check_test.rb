# frozen_string_literal: true

require "test_helper"

module Ai
  module Composer
    class GentlenessCheckTest < ActiveSupport::TestCase
      def with_stub_env
        prior = ENV["AI_MODERATION_STUB"]
        ENV["AI_MODERATION_STUB"] = "1"
        yield
      ensure
        ENV["AI_MODERATION_STUB"] = prior
      end

      test "returns gentle for soft text" do
        with_stub_env do
          result = GentlenessCheck.call(content: "Just resting in the Lord's grace today, brothers.")
          assert result.gentle?
          assert_equal "", result.nudge
          assert_equal "", result.suggestion
        end
      end

      test "returns harsh and a suggestion when contemptuous language is used" do
        with_stub_env do
          result = GentlenessCheck.call(content: "You are an idiot for thinking that.")
          assert result.harsh?
          refute_equal "", result.nudge
          refute_equal "", result.suggestion
        end
      end
    end
  end
end

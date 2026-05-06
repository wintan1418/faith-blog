# frozen_string_literal: true

require "test_helper"

module Ai
  module Moderation
    class ClientTest < ActiveSupport::TestCase
      def with_env(values)
        originals = {}
        values.each do |k, v|
          originals[k] = ENV[k]
          ENV[k] = v
        end
        yield
      ensure
        originals.each { |k, v| ENV[k] = v }
      end

      test "stub flag wins over every other env var" do
        with_env(
          "AI_MODERATION_STUB"     => "1",
          "AI_MODERATION_PROVIDER" => "openai",
          "GEMINI_API_KEY"         => "g",
          "OPENAI_API_KEY"         => "o",
          "ANTHROPIC_API_KEY"      => "a"
        ) do
          assert_equal "stub", Client.resolve_provider_name
          assert Client.stub?
        end
      end

      test "explicit AI_MODERATION_PROVIDER picks that provider when its key is present" do
        with_env(
          "AI_MODERATION_STUB"     => nil,
          "AI_MODERATION_PROVIDER" => "openai",
          "GEMINI_API_KEY"         => nil,
          "OPENAI_API_KEY"         => "test_key",
          "ANTHROPIC_API_KEY"      => nil
        ) do
          assert_equal "openai", Client.resolve_provider_name
        end
      end

      test "with no explicit provider, gemini wins when only its key is set" do
        with_env(
          "AI_MODERATION_STUB"     => nil,
          "AI_MODERATION_PROVIDER" => nil,
          "GEMINI_API_KEY"         => "g",
          "OPENAI_API_KEY"         => nil,
          "ANTHROPIC_API_KEY"      => nil
        ) do
          assert_equal "gemini", Client.resolve_provider_name
        end
      end

      test "with no provider explicitly set, the order is gemini > openai > anthropic" do
        with_env(
          "AI_MODERATION_STUB"     => nil,
          "AI_MODERATION_PROVIDER" => nil,
          "GEMINI_API_KEY"         => "g",
          "OPENAI_API_KEY"         => "o",
          "ANTHROPIC_API_KEY"      => "a"
        ) do
          assert_equal "gemini", Client.resolve_provider_name
        end
      end

      test "falls back to stub when no key is set anywhere" do
        with_env(
          "AI_MODERATION_STUB"     => nil,
          "AI_MODERATION_PROVIDER" => nil,
          "GEMINI_API_KEY"         => nil,
          "OPENAI_API_KEY"         => nil,
          "ANTHROPIC_API_KEY"      => nil
        ) do
          assert_equal "stub", Client.resolve_provider_name
        end
      end

      test "explicit provider without its key still falls back via the auto-resolver" do
        with_env(
          "AI_MODERATION_STUB"     => nil,
          "AI_MODERATION_PROVIDER" => "openai",
          "GEMINI_API_KEY"         => "g",
          "OPENAI_API_KEY"         => nil,
          "ANTHROPIC_API_KEY"      => nil
        ) do
          assert_equal "gemini", Client.resolve_provider_name
        end
      end
    end
  end
end

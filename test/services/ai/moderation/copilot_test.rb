# frozen_string_literal: true

require "test_helper"

module Ai
  module Moderation
    class CopilotTest < ActiveSupport::TestCase
      setup do
        ENV["AI_MODERATION_STUB"] = "1"
        ENV["ANTHROPIC_API_KEY"] = nil
        ENV["GEMINI_API_KEY"] = nil
        ENV["OPENAI_API_KEY"] = nil
      end

      def make_user
        User.create!(
          username: "u_#{SecureRandom.hex(3)}",
          email: "u_#{SecureRandom.hex(3)}@example.com",
          password: "password123",
          password_confirmation: "password123"
        )
      end

      def make_room
        Room.create!(name: "Room #{SecureRandom.hex(3)}", description: "x")
      end

      def make_review
        user = make_user
        post = Post.create!(
          user: user, room: make_room,
          title: "A breath worth sharing",
          content: "I want to talk about something hard.",
          status: :published
        )
        AiModerationReview.create!(
          reviewable: post, user: user,
          status: :flagged, severity: "medium",
          recommended_action: "require_review",
          categories: %w[harassment],
          score: 0.6, summary: "rude language",
          model: "stub", raw_response: {}, reviewed_at: Time.current
        )
      end

      test "responds with strings for every supported operation" do
        review = make_review
        Copilot::OPERATIONS.each do |op|
          out = Copilot.call(operation: op, review: review)
          assert out.is_a?(String), "#{op} should return a String"
          assert out.length.positive?, "#{op} should return non-empty text"
        end
      end

      test "summarize works on a Post-backed review" do
        review = make_review
        out = Copilot.call(operation: "summarize", review: review)
        # Stub provider returns a JSON-shaped payload as content; just
        # confirm we got non-empty text back without raising.
        assert out.is_a?(String)
        refute out.empty?
      end
    end
  end
end

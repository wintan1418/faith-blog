# frozen_string_literal: true

require "test_helper"

module Ai
  module Moderation
    class PolicyTest < ActiveSupport::TestCase
      test "severity_to_action maps high to hide_pending_review" do
        assert_equal "hide_pending_review", Policy.severity_to_action("high")
      end

      test "severity_to_action maps medium to require_review" do
        assert_equal "require_review", Policy.severity_to_action("medium")
      end

      test "severity_to_action maps low and unknown to allow" do
        assert_equal "allow", Policy.severity_to_action("low")
        assert_equal "allow", Policy.severity_to_action("none")
        assert_equal "allow", Policy.severity_to_action("nonsense")
      end

      test "categories list covers high-severity buckets from the plan" do
        %w[violence self_harm sexual_exploitation hate harassment scam doxxing].each do |c|
          assert_includes Policy::CATEGORIES, c, "missing category: #{c}"
        end
      end

      test "categories list covers community-specific buckets" do
        %w[spiritual_manipulation predatory_fundraising dangerous_medical_advice fake_testimony].each do |c|
          assert_includes Policy::CATEGORIES, c, "missing community category: #{c}"
        end
      end

      test "risk levels match plan vocabulary" do
        assert_equal %w[clear watch restricted suspended banned], Policy::RISK_LEVELS
      end
    end
  end
end

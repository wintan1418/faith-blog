# frozen_string_literal: true

module Ai
  module Moderation
    # Synchronous gate that runs before a Post becomes visible on the feed.
    # It calls the existing Reviewer to classify the content and returns one of:
    #   :allow  — publish normally
    #   :hold   — moderation_status :pending_review, hidden from feed, admin queue
    #   :block  — moderation_status :blocked, hidden, prominent admin queue marker
    #
    # Designed to fail open: any AI error (network, parse, timeout) returns :allow
    # plus an audit log entry, so a flaky upstream cannot stop legitimate posting.
    class PostGatekeeper
      Verdict = Struct.new(:decision, :reason, :severity, :categories, :recommended_action,
                           :result, keyword_init: true) do
        def block? = decision == :block
        def hold?  = decision == :hold
        def allow? = decision == :allow

        # Persist the AiModerationReview record now that the post has been saved.
        # No-op when fail-open returned no result (network/parse error).
        def persist_review!(post)
          return nil unless result
          AiModerationReview.from_result(reviewable: post, user: post.user, result: result)
        end
      end

      # Hard-block the moment the LLM names any of these categories with severity=high.
      HARD_BLOCK_CATEGORIES = %w[
        explicit_adult
        sexual_exploitation
        hate
        harassment
        violence
        self_harm
        doxxing
        scam
      ].freeze

      def self.call(post:)
        new(post: post).call
      end

      def initialize(post:)
        @post = post
      end

      def call
        result = Reviewer.call(
          content: extract_content,
          kind: "post",
          author_context: author_context
        )
        decision, reason = decide(result)
        Verdict.new(
          decision: decision,
          reason: reason,
          severity: result.severity,
          categories: result.categories,
          recommended_action: result.recommended_action,
          result: result
        )
      rescue Client::Error, Reviewer::ParseError, Net::ReadTimeout, Net::OpenTimeout, StandardError => e
        Rails.logger.warn("[PostGatekeeper] fail-open: #{e.class}: #{e.message}")
        Verdict.new(decision: :allow, reason: "moderation_unavailable", severity: "none",
                    categories: [], recommended_action: "allow", result: nil)
      end

      private

      def extract_content
        [@post.title, @post.content&.to_plain_text].compact.reject(&:blank?).join("\n\n")
      end

      def author_context
        user = @post.user
        return nil unless user

        parts = []
        parts << "account_age_days=#{((Time.current - user.created_at) / 1.day).to_i}"
        parts << "risk_level=#{user.risk_profile&.risk_level || "clear"}" if user.respond_to?(:risk_profile)
        parts.join(" ")
      end

      def decide(result)
        action = result.recommended_action.to_s
        severity = result.severity.to_s
        cats = Array(result.categories).map(&:to_s)

        return [:block, "explicit_category"] if severity == "high" && (HARD_BLOCK_CATEGORIES & cats).any?
        return [:block, "policy_block"]      if action == "block"
        return [:hold,  "hide_pending_review"] if action == "hide_pending_review"
        return [:hold,  "require_review"]     if action == "require_review"
        return [:hold,  "suggest_edit"]       if action == "suggest_edit" && severity != "low"

        [:allow, "ok"]
      end
    end
  end
end

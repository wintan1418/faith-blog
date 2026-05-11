# frozen_string_literal: true

module Ai
  module Moderation
    # Synchronous gate for new comments, mirroring PostGatekeeper. Same three
    # decisions (allow/hold/block), same fail-open behavior, same hard-block
    # category list — comments that would be hidden if posted as a breath should
    # also be hidden when posted as a reply.
    class CommentGatekeeper
      Verdict               = PostGatekeeper::Verdict
      HARD_BLOCK_CATEGORIES = PostGatekeeper::HARD_BLOCK_CATEGORIES

      def self.call(comment:)
        new(comment: comment).call
      end

      def initialize(comment:)
        @comment = comment
      end

      def call
        result = Reviewer.call(
          content: extract_content,
          kind: "comment",
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
        Rails.logger.warn("[CommentGatekeeper] fail-open: #{e.class}: #{e.message}")
        Verdict.new(decision: :allow, reason: "moderation_unavailable", severity: "none",
                    categories: [], recommended_action: "allow", result: nil)
      end

      private

      def extract_content
        @comment.content&.to_plain_text.to_s
      end

      def author_context
        user = @comment.user
        return nil unless user

        parts = []
        parts << "account_age_days=#{((Time.current - user.created_at) / 1.day).to_i}"
        parts << "risk_level=#{user.risk_profile&.risk_level || "clear"}" if user.respond_to?(:risk_profile)
        parts.join(" ")
      end

      def decide(result)
        action   = result.recommended_action.to_s
        severity = result.severity.to_s
        cats     = Array(result.categories).map(&:to_s)

        return [:block, "explicit_category"]   if severity == "high" && (HARD_BLOCK_CATEGORIES & cats).any?
        return [:block, "policy_block"]        if action == "block"
        return [:hold,  "hide_pending_review"] if action == "hide_pending_review"
        return [:hold,  "require_review"]      if action == "require_review"
        return [:hold,  "suggest_edit"]        if action == "suggest_edit" && severity != "low"

        [:allow, "ok"]
      end
    end
  end
end

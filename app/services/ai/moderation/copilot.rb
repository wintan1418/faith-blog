# frozen_string_literal: true

module Ai
  module Moderation
    # Single-call helpers for moderators reviewing flagged content.
    # Each method returns a plain String — short, ready to paste into
    # a notes box, a warning message, or a decision summary.
    class Copilot
      class Error < StandardError; end

      OPERATIONS = %w[summarize suggest_action draft_warning].freeze

      def self.call(operation:, review:)
        new(review: review).public_send(operation)
      end

      def initialize(review:)
        @review = review
        @user   = review.user
      end

      def summarize
        run(
          system: <<~PROMPT,
            You are a moderator's assistant. Summarize a single flagged piece of
            content in 2 short sentences for a busy moderator. State what was
            said, why the AI flagged it, and the most important context. No
            preamble. No lists. Plain prose, neutral tone.
          PROMPT
          user: content_block
        )
      end

      def suggest_action
        run(
          system: <<~PROMPT,
            You are a moderation policy advisor for a Christian faith community.
            Given a flagged piece of content plus the author's prior moderation
            history, recommend ONE specific action: approve, dismiss, hide,
            warn, restrict, or suspend. Justify in 1-2 sentences. Be conservative.
            Bias toward 'warn' over 'restrict' on first-time medium severity.
            Bias toward 'hide' on high severity even if first offense.
            Format your reply as: "<ACTION>: <one or two sentence reason>".
          PROMPT
          user: full_context_block
        )
      end

      def draft_warning
        run(
          system: <<~PROMPT,
            You are a kind, firm pastor-moderator. Write a short private warning
            (under 80 words) to a community member whose recent post was flagged.
            Be specific about what was problematic, restate the community
            standard once, invite them back into good standing. No bullet
            points. No preamble. Address them by their handle in the second
            person. Sign off as "— The Brethreign team".
          PROMPT
          user: content_block + "\n\nUser handle: @#{@user&.username || "member"}"
        )
      end

      private

      def run(system:, user:)
        raw = Client.call(system: system, user: user)
        text = Array(raw["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s.strip
        text.presence || "(no response from AI)"
      rescue Client::Error => e
        raise Error, e.message
      end

      def content_block
        reviewable = @review.reviewable
        body = case reviewable
               when Post    then [ reviewable.title, reviewable.content.to_plain_text ].compact.join("\n\n")
               when Comment then reviewable.content.to_plain_text.to_s
               else reviewable.try(:body).to_s
               end

        <<~CTX
          AI severity: #{@review.severity}
          AI categories: #{@review.categories.join(", ").presence || "none"}
          AI summary: #{@review.summary}
          --- content ---
          #{body}
          ---
        CTX
      end

      def full_context_block
        history = if @user
                    flagged   = @user.respond_to?(:ai_moderation_reviews) ? @user.ai_moderation_reviews.where(status: %i[flagged actioned]).count : 0
                    risk      = @user.risk_profile&.risk_level || "clear"
                    age_days  = ((Time.current - @user.created_at) / 1.day).to_i
                    "User account: @#{@user.username} | risk_level=#{risk} | flagged_reviews=#{flagged} | account_age_days=#{age_days}"
                  else
                    "User account: (anonymous)"
                  end

        "#{content_block}\n\n#{history}"
      end
    end
  end
end

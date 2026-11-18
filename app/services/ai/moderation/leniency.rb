# frozen_string_literal: true

module Ai
  module Moderation
    # What the AI may take down on its own, and what only goes to a moderator.
    #
    # Brethreign protects people without policing them: almost everything is
    # published straight away, and the AI only alerts a moderator. It removes
    # content by itself only for the few things that must never be seen even
    # for a moment. Everything else a moderator decides.
    module Leniency
      # Removed when the AI is at least fairly sure (severity medium or high).
      ALWAYS_REMOVE = %w[explicit_adult sexual_exploitation].freeze
      # Removed only when the AI is sure (severity high): credible threats,
      # someone's private details, a clear scam.
      REMOVE_WHEN_HIGH = %w[violence doxxing scam].freeze

      module_function

      def categories(result) = Array(result&.categories).map(&:to_s)

      def remove?(result)
        return false unless result
        cats = categories(result)
        severity = result.severity.to_s
        return true if severity.in?(%w[medium high]) && (cats & ALWAYS_REMOVE).any?
        severity == "high" && (cats & REMOVE_WHEN_HIGH).any?
      end

      # Worth a moderator's look (stays visible).
      def flag?(result)
        return false unless result
        result.severity.to_s.in?(%w[medium high]) ||
          result.recommended_action.to_s.in?(%w[block hide_pending_review require_review])
      end
    end
  end
end

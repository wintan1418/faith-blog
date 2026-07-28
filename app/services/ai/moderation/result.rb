# frozen_string_literal: true

module Ai
  module Moderation
    Result = Struct.new(
      :safe,
      :severity,
      :categories,
      :score,
      :summary,
      :recommended_action,
      :raw_response,
      :model,
      keyword_init: true
    ) do
      def to_h
        {
          safe: safe,
          severity: severity,
          categories: categories,
          score: score,
          summary: summary,
          recommended_action: recommended_action,
          raw_response: raw_response,
          model: model
        }
      end

      def flagged?
        !safe
      end

      # Synthetic clean verdict for authors who skip the AI gate on trust.
      # Persisted like any other result so the moderation board and the
      # backlog sweep see a settled review.
      def self.trusted_skip
        new(
          safe: true,
          severity: "none",
          categories: [],
          score: 0.0,
          summary: "Trusted author — AI gate skipped.",
          recommended_action: "allow",
          raw_response: { source: "trust_gate" },
          model: "trust-gate"
        )
      end
    end
  end
end

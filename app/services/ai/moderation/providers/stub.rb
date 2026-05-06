# frozen_string_literal: true

module Ai
  module Moderation
    module Providers
      class Stub < Base
        DEFAULT_MODEL = "stub"

        FLAGGED_KEYWORDS = %w[kill suicide bomb scam phish stupid hate].freeze

        def call(system:, user:)
          match = FLAGGED_KEYWORDS.find { |w| user.to_s.downcase.include?(w) }

          payload =
            if match
              severity = %w[kill bomb suicide].include?(match) ? "high" : "medium"
              {
                safe: false,
                severity: severity,
                categories: [ category_for(match) ],
                score: severity == "high" ? 0.92 : 0.65,
                summary: "Stub flagged content matched keyword '#{match}'.",
                recommended_action: Policy.severity_to_action(severity)
              }
            else
              {
                safe: true,
                severity: "none",
                categories: [],
                score: 0.05,
                summary: "Stub review found no obvious violations.",
                recommended_action: "allow"
              }
            end

          wrap(model: "stub", text: JSON.dump(payload))
        end

        private

        def category_for(word)
          case word
          when "kill", "bomb"  then "violence"
          when "suicide"       then "self_harm"
          when "scam", "phish" then "scam"
          when "hate"          then "hate"
          when "stupid"        then "harassment"
          else "heated_language"
          end
        end
      end
    end
  end
end

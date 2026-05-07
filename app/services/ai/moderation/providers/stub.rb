# frozen_string_literal: true

module Ai
  module Moderation
    module Providers
      class Stub < Base
        DEFAULT_MODEL = "stub"

        FLAGGED_KEYWORDS = %w[kill suicide bomb scam phish stupid hate].freeze
        HARSH_KEYWORDS   = %w[idiot stupid moron loser shut\ up].freeze

        def call(system:, user:)
          # Composer assistants share this provider; branch on the task marker
          # in the system prompt so each task gets the right shape back.
          return wrap(model: "stub", text: JSON.dump(gentleness_payload(user))) if system.to_s.include?("[TASK:GENTLENESS]")
          return wrap(model: "stub", text: JSON.dump(scripture_payload(user)))  if system.to_s.include?("[TASK:SCRIPTURE]")

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

        def gentleness_payload(user)
          text = user.to_s.downcase
          if HARSH_KEYWORDS.any? { |w| text.include?(w) }
            {
              tone: "harsh",
              confidence: 0.78,
              summary: "Stub detected harsh language toward a person.",
              nudge: "This may land as contempt — would softer wording carry the same truth?",
              suggestion: "Consider naming the action you disagree with rather than the person."
            }
          else
            {
              tone: "gentle",
              confidence: 0.9,
              summary: "Stub found nothing concerning in tone.",
              nudge: "",
              suggestion: ""
            }
          end
        end

        def scripture_payload(user)
          text = user.to_s.downcase
          return { verses: [] } if text.length < 40

          if text.include?("anxious") || text.include?("worry") || text.include?("fear")
            { verses: [
              { reference: "Philippians 4:6-7", reason: "An invitation to trade anxiety for peace through prayer." },
              { reference: "Psalm 34:4", reason: "A reminder that God answers when we seek Him in fear." }
            ] }
          elsif text.include?("thank") || text.include?("grateful")
            { verses: [ { reference: "1 Thessalonians 5:18", reason: "Thanksgiving as the steady posture of faith." } ] }
          else
            { verses: [ { reference: "Psalm 46:10", reason: "Stillness as a doorway into knowing God." } ] }
          end
        end

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

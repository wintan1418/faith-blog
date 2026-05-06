# frozen_string_literal: true

module Ai
  module Moderation
    module Policy
      SEVERITIES = %w[none low medium high].freeze

      CATEGORIES = %w[
        violence
        self_harm
        sexual_exploitation
        hate
        harassment
        scam
        explicit_adult
        doxxing
        spiritual_manipulation
        predatory_fundraising
        dangerous_medical_advice
        theological_personal_attack
        fake_testimony
        spam
        heated_language
        off_topic
        duplicate
        misleading_claim
        needs_room_change
        needs_content_warning
      ].freeze

      ACTIONS = %w[
        allow
        suggest_edit
        require_review
        hide_pending_review
        block
      ].freeze

      THRESHOLDS = {
        hide_pending_review: 0.85,
        require_review: 0.55,
        suggest_edit: 0.30
      }.freeze

      RISK_LEVELS = %w[clear watch restricted suspended banned].freeze

      def self.severity_to_action(severity)
        case severity
        when "high"   then "hide_pending_review"
        when "medium" then "require_review"
        when "low"    then "allow"
        else "allow"
        end
      end
    end
  end
end

# frozen_string_literal: true

module Ai
  module Moderation
    # Recomputes a user's risk_profile after a new AI review lands.
    # Conservative — only escalates risk_level on flagged reviews,
    # never auto-suspends/bans (that stays a moderator decision).
    class RiskScorer
      WATCH_THRESHOLD      = 1   # any flagged review puts user on watch
      RESTRICTED_THRESHOLD = 3   # 3+ flagged reviews -> restricted

      def self.call(user:)
        new(user: user).call
      end

      def initialize(user:)
        @user = user
      end

      def call
        return unless @user

        profile = @user.risk_profile || @user.create_risk_profile!(risk_level: :clear)

        flagged_count   = @user.ai_moderation_reviews.where(status: %i[flagged actioned]).count
        last_flagged_at = @user.ai_moderation_reviews.where(status: %i[flagged actioned]).maximum(:reviewed_at)

        new_level = next_level(profile, flagged_count)
        new_score = score_for(flagged_count)

        profile.update!(
          flagged_reviews_count: flagged_count,
          last_flagged_at: last_flagged_at,
          risk_level: new_level,
          risk_score: new_score
        )

        profile
      end

      private

      # Never auto-demote moderator-set levels (suspended/banned).
      def next_level(profile, flagged_count)
        return profile.risk_level if %w[suspended banned].include?(profile.risk_level)

        if flagged_count >= RESTRICTED_THRESHOLD
          "restricted"
        elsif flagged_count >= WATCH_THRESHOLD
          "watch"
        else
          "clear"
        end
      end

      def score_for(flagged_count)
        # Clamp to 0..1; saturates around 5 flags.
        [ flagged_count / 5.0, 1.0 ].min.round(3)
      end
    end
  end
end

# frozen_string_literal: true

class AiModerationReview < ApplicationRecord
  belongs_to :reviewable, polymorphic: true
  belongs_to :user, optional: true
  has_many :moderation_logs, dependent: :nullify

  enum :status, {
    pending:         0,
    cleared:         1,
    flagged:         2,
    actioned:        3,
    dismissed:       4
  }

  SEVERITIES = Ai::Moderation::Policy::SEVERITIES
  validates :severity, inclusion: { in: SEVERITIES }
  validates :recommended_action, inclusion: { in: Ai::Moderation::Policy::ACTIONS }

  scope :recent,            -> { order(reviewed_at: :desc) }
  scope :needs_attention,   -> { where(status: %i[pending flagged]) }
  scope :high_severity,     -> { where(severity: "high") }
  scope :for_category,      ->(c) { where("? = ANY(categories)", c) }

  def flagged_content?
    %w[low medium high].include?(severity) && severity != "none"
  end

  # `status` override: the moderation decision (hold → :pending,
  # block → :flagged) outranks result.safe — the admin queue only lists
  # pending/flagged, so a held post with a :cleared review is invisible.
  def self.from_result(reviewable:, user:, result:, status: nil)
    review = find_or_initialize_by(reviewable: reviewable)
    review.assign_attributes(
      user: user,
      status: status || (result.flagged? ? :flagged : :cleared),
      severity: result.severity,
      recommended_action: result.recommended_action,
      categories: result.categories,
      score: result.score,
      summary: result.summary,
      model: result.model,
      raw_response: result.raw_response,
      reviewed_at: Time.current
    )
    review.save!
    review
  end
end

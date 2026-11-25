# frozen_string_literal: true

# One member's answer to a FeedbackCampaign, and the feed pop-up's memory for
# them (snoozed until, how many times, or "don't ask again"). Unique per
# member per campaign, so nobody answers twice.
class FeedbackResponse < ApplicationRecord
  SNOOZE_FOR = 2.days
  MAX_SNOOZES = 3
  PLATFORMS = %w[web android_app ios_app].freeze
  PLATFORM_LABELS = { "web" => "Web", "android_app" => "Android app", "ios_app" => "iPhone app" }.freeze

  belongs_to :feedback_campaign, counter_cache: false
  belongs_to :user

  validates :user_id, uniqueness: { scope: :feedback_campaign_id }
  validates :comment, length: { maximum: 2000 }, allow_blank: true
  validates :platform, inclusion: { in: PLATFORMS }, allow_nil: true
  validate :answer_fits_campaign, if: :submitted?

  scope :submitted, -> { where.not(submitted_at: nil) }
  scope :newest, -> { order(submitted_at: :desc, id: :desc) }

  def submitted? = submitted_at.present?
  def declined? = declined_at.present?

  # May the feed pop-up show this campaign again?
  def promptable?(now: Time.current)
    return false if submitted? || declined?
    return false if snooze_count >= MAX_SNOOZES
    return false if snoozed_until.present? && snoozed_until > now

    true
  end

  def platform_label = PLATFORM_LABELS[platform] || "—"

  # Saves the answer (once). Returns true when saved now.
  def submit!(rating:, comment: nil, choice: nil, platform: nil, at: Time.current)
    return false if submitted?

    self.rating = rating.presence&.to_i
    self.comment = comment.to_s.strip.first(2000).presence
    self.choice = choice.to_s.strip.presence
    self.platform = platform if PLATFORMS.include?(platform)
    self.submitted_at = at
    return false unless save

    FeedbackCampaign.where(id: feedback_campaign_id).update_all("responses_count = responses_count + 1")
    Seeds.feedback_given(self)
    true
  end

  def snooze!(at: Time.current)
    return false if submitted? || declined?

    update!(snoozed_until: at + SNOOZE_FOR, snooze_count: snooze_count + 1)
  end

  def decline!(at: Time.current)
    return false if submitted?

    update!(declined_at: at)
  end

  private

  def answer_fits_campaign
    campaign = feedback_campaign
    return unless campaign

    errors.add(:rating, "is needed") if rating.nil?
    errors.add(:rating, "is out of range") if rating && !campaign.rating_range.cover?(rating)
    errors.add(:choice, "isn't one of the answers") if choice.present? && !campaign.choice_options.include?(choice)
  end
end

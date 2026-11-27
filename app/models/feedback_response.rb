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

  # A longer survey's reply to one question: a string, a list, or nil.
  def answer_for(question)
    answers.to_h[question["key"]].presence
  end

  # "Nigeria" / "Rooms, Messages" / the text, for lists and the CSV.
  def answer_text(question) = Array(answer_for(question)).join(", ")

  # Saves the answer (once). Returns true when saved now.
  def submit!(rating:, comment: nil, choice: nil, answers: nil, platform: nil, at: Time.current)
    return false if submitted?

    self.rating = rating.presence&.to_i
    self.comment = comment.to_s.strip.first(2000).presence
    self.choice = choice.to_s.strip.presence
    self.answers = tidy_answers(answers)
    self.platform = platform if PLATFORMS.include?(platform)
    self.submitted_at = at
    unless save
      self.submitted_at = nil # not sent: the page shows the form and the error again
      return false
    end

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

  # Only this campaign's questions, in the right shape: one → a string,
  # many → a list, text → up to 2,000 characters.
  def tidy_answers(raw)
    campaign = feedback_campaign
    return {} unless campaign&.long_form? && raw.respond_to?(:to_h)

    raw = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw.to_h
    campaign.answer_questions.each_with_object({}) do |q, out|
      value = raw[q["key"]] || raw[q["key"].to_sym]
      case q["kind"]
      when "one"  then out[q["key"]] = value.to_s.strip if value.present?
      when "many" then (list = Array(value).map { |v| v.to_s.strip }.compact_blank.uniq).any? && out[q["key"]] = list
      when "text" then out[q["key"]] = value.to_s.strip.first(2000) if value.to_s.strip.present?
      end
    end
  end

  def answer_fits_campaign
    campaign = feedback_campaign
    return unless campaign

    errors.add(:rating, "is needed") if rating.nil?
    errors.add(:rating, "is out of range") if rating && !campaign.rating_range.cover?(rating)
    errors.add(:choice, "isn't one of the answers") if choice.present? && !campaign.choice_options.include?(choice)
    answers_fit_questions(campaign) if campaign.long_form?
  end

  def answers_fit_questions(campaign)
    numbers = campaign.form_questions.each_with_index.to_h { |q, i| [ q["key"], i + 1 ] }
    missing = []
    campaign.answer_questions.each do |q|
      value = answers.to_h[q["key"]]
      if value.blank?
        missing << numbers[q["key"]] if %w[one many].include?(q["kind"]) && !q["optional"]
        next
      end
      picks = Array(value)
      errors.add(:base, "Question #{numbers[q['key']]} has an answer that isn't on the list") if %w[one many].include?(q["kind"]) && (picks - q["options"]).any?
      errors.add(:base, "Question #{numbers[q['key']]} allows up to #{q['max']} picks") if q["kind"] == "many" && q["max"] && picks.size > q["max"]
    end
    errors.add(:base, "Please answer #{'question'.pluralize(missing.size)} #{missing.to_sentence}") if missing.any?
  end
end

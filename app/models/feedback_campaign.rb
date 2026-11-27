# frozen_string_literal: true

# An admin-run survey: "How is Brethreign working for you?". Members answer
# once, from an alert or from a pop-up on the feed (FeedbackCampaign.prompt_for).
#
# Life: draft → launched (now, or scheduled for starts_at) → live until ends_at
# or until an admin closes it. Launching delivers one alert to every targeted
# member (FeedbackCampaignDeliveryJob), in batches, with a push only when the
# admin ticked "also push".
class FeedbackCampaign < ApplicationRecord
  enum :rating_kind, { stars: 0, nps: 1 }, prefix: :rating
  enum :audience, { everyone: 0, active_recently: 1, new_members: 2, web: 3, android_app: 4, ios_app: 5 }, prefix: :audience

  AUDIENCE_LABELS = {
    "everyone"        => "Everyone",
    "active_recently" => "Active in the last 30 days",
    "new_members"     => "New members (joined in the last 14 days)",
    "web"             => "People using the website",
    "android_app"     => "People using the Android app",
    "ios_app"         => "People using the iPhone app"
  }.freeze
  ACTIVE_WINDOW = 30.days
  NEW_MEMBER_WINDOW = 14.days
  # A platform audience is whoever used that platform in this window (Ahoy visits).
  PLATFORM_WINDOW = 60.days
  MAX_CHOICES = 6
  # A longer survey's own questions (see #questions_text for how admins write them).
  QUESTION_KINDS = %w[one many text rating].freeze
  MAX_QUESTIONS = 20
  MAX_OPTIONS = 12
  # Rough reading-and-tapping time per question, for "about 3 minutes".
  SECONDS_PER_QUESTION = 15
  # Members can opt out of surveys in Settings → Notifications (a remembered card key).
  OPT_OUT_KEY = "no-feedback-surveys"
  # After answering or declining one survey, the pop-up rests this long before the next.
  REST_BETWEEN_SURVEYS = 7.days

  belongs_to :created_by, class_name: "User", optional: true
  has_many :responses, class_name: "FeedbackResponse", dependent: :delete_all
  has_many :notifications, as: :notifiable, dependent: :delete_all

  validates :title, presence: true, length: { maximum: 160 }
  validates :follow_up_prompt, :choice_question, length: { maximum: 200 }, allow_blank: true
  validate :ends_after_start
  validate :choices_complete
  validate :questions_complete

  before_validation :tidy_choices
  before_validation :tidy_questions

  scope :recent, -> { order(created_at: :desc) }
  # Launched, started, not ended and not closed.
  scope :live, -> {
    now = Time.current
    where.not(launched_at: nil).where(closed_at: nil)
         .where(starts_at: ..now)
         .where("feedback_campaigns.ends_at IS NULL OR feedback_campaigns.ends_at > ?", now)
  }

  def self.audience_options = AUDIENCE_LABELS.map { |key, label| [ label, key ] }

  # ── State ─────────────────────────────────────────────────────────────

  def draft? = launched_at.nil?
  def closed? = closed_at.present?
  def ended? = closed? || (ends_at.present? && ends_at <= Time.current)
  def scheduled? = !draft? && !ended? && starts_at.present? && starts_at > Time.current
  def live? = !draft? && !ended? && !scheduled?

  def status
    if draft? then "draft"
    elsif closed? then "closed"
    elsif ended? then "ended"
    elsif scheduled? then "scheduled"
    else "live"
    end
  end

  # Launch now (starts_at blank or past) or at starts_at. Returns false if it
  # can't be launched (already launched, or already over).
  def launch!(at: Time.current)
    return false unless draft?
    return false if ends_at.present? && ends_at <= at

    self.starts_at = at if starts_at.blank? || starts_at < at
    self.launched_at = at
    save!
    FeedbackCampaignDeliveryJob.set(wait_until: starts_at).perform_later(id)
    true
  end

  def close!(at: Time.current)
    return false if closed?

    update!(closed_at: at)
    # The alert stays in the list, but no longer counts as new.
    notifications.unread.update_all(read_at: at)
    true
  end

  # ── Questions ─────────────────────────────────────────────────────────

  def rating_range = rating_nps? ? (0..10) : (1..5)

  def rating_question
    rating_nps? ? "How likely are you to recommend Brethreign to a friend?" : nil
  end

  def choice_options_text = choice_options.join("\n")

  def choices? = choice_question.present? && choice_options.size >= 2

  # ── Longer surveys ────────────────────────────────────────────────────
  #
  # `questions` is a list of hashes: key ("q1"…), kind (one / many / text /
  # rating), text, and optionally hint, options, max (for many) and optional.
  # The rating's answer lives in FeedbackResponse#rating; the rest in #answers.

  def long_form? = questions.present?

  # The questions in the order members see them. A long survey without a
  # rating entry gets the rating first.
  def form_questions
    return [] unless long_form?
    return questions if questions.any? { |q| q["kind"] == "rating" }

    [ { "key" => "rating", "kind" => "rating", "text" => rating_question || title } ] + questions
  end

  def answer_questions = questions.reject { |q| q["kind"] == "rating" }

  def question_count = long_form? ? form_questions.size : [ 1, (choices? ? 1 : 0), (follow_up_prompt.present? ? 1 : 0) ].sum

  def duration_label
    return "30 seconds" unless long_form?

    minutes = [ (question_count * SECONDS_PER_QUESTION / 60.0).round, 1 ].max
    "about #{minutes} #{'minute'.pluralize(minutes)}"
  end

  # Admins write questions as plain text, one block per question:
  #
  #   # one: Where do you live?
  #   Nigeria
  #   Ghana
  #
  #   # many 3: What should we build next?
  #   > Pick up to 3.
  #   Job board
  #   Calls
  #
  #   # text: What do you love most?
  #   # rating: How likely are you to recommend Brethreign?
  #   # one optional: Can we reach out to you?
  #
  # "many 3" allows up to three picks; "optional" lets members skip it;
  # a line starting with ">" is a hint under the question.
  QUESTION_HEADER = /\A#\s*(one|many|text|rating)(?:\s+(\d+))?(\s+optional)?\s*:\s*(.+)\z/i

  def questions_text
    questions.map do |q|
      head = "# #{q['kind']}#{" #{q['max']}" if q['max']}#{' optional' if q['optional']}: #{q['text']}"
      [ head, (q["hint"] && "> #{q['hint']}"), *Array(q["options"]) ].compact.join("\n")
    end.join("\n\n")
  end

  def questions_text=(text)
    @question_errors = []
    parsed = []
    text.to_s.split(/\r?\n/).each do |raw|
      line = raw.strip
      next if line.empty?

      if (m = line.match(QUESTION_HEADER))
        parsed << { "kind" => m[1].downcase, "max" => m[2]&.to_i, "optional" => m[3].present?, "text" => m[4].strip, "options" => [] }
      elsif parsed.empty?
        @question_errors << "start each question with a line like “# one: Your question?” (found “#{line.first(40)}”)"
      elsif line.start_with?(">")
        parsed.last["hint"] = line.delete_prefix(">").strip
      else
        parsed.last["options"] << line
      end
    end
    self.questions = parsed
  end

  # { option => count } for a one / many question, over submitted answers.
  def question_counts(question)
    tally = Hash.new(0)
    answered.pluck(:answers).each do |answers|
      Array(answers[question["key"]]).each { |value| tally[value] += 1 }
    end
    Array(question["options"]).to_h { |option| [ option, tally[option] ] }
  end

  def question_answered_count(question)
    answered.pluck(:answers).count { |answers| Array(answers[question["key"]]).any?(&:present?) }
  end

  def audience_label = AUDIENCE_LABELS.fetch(audience.to_s, audience.to_s.humanize)

  # ── Audience ──────────────────────────────────────────────────────────

  # Every member this campaign is for. Excludes deactivated accounts, the
  # site health monitor, and members who opted out of surveys.
  def audience_scope(now: Time.current)
    scope = User.active.where.not("? = ANY(users.dismissed_cards)", OPT_OUT_KEY)
    case audience.to_s
    when "active_recently" then scope.where(last_seen_at: (now - ACTIVE_WINDOW)..)
    when "new_members"     then scope.where(created_at: (now - NEW_MEMBER_WINDOW)..)
    when "web", "android_app", "ios_app"
      scope.where(id: Ahoy::Visit.where(platform: audience.to_s, started_at: (now - PLATFORM_WINDOW)..).where.not(user_id: nil).select(:user_id))
    else scope
    end
  end

  def includes_user?(user, now: Time.current)
    return false unless user&.persisted?

    audience_scope(now: now).where(id: user.id).exists?
  end

  # ── Results ───────────────────────────────────────────────────────────

  def answered = responses.submitted

  def response_rate
    return nil if targeted_count.to_i.zero?

    (answered.count * 100.0 / targeted_count).round(1)
  end

  def average_rating
    avg = answered.where.not(rating: nil).average(:rating)
    avg&.to_f&.round(2)
  end

  # Net Promoter Score: % promoters (9–10) minus % detractors (0–6).
  def nps_score
    ratings = answered.where.not(rating: nil).pluck(:rating)
    return nil if ratings.empty?

    promoters = ratings.count { |r| r >= 9 }
    detractors = ratings.count { |r| r <= 6 }
    ((promoters - detractors) * 100.0 / ratings.size).round
  end

  # { rating => count } for every possible rating (zeros included).
  def distribution
    counts = answered.where.not(rating: nil).group(:rating).count
    rating_range.to_h { |r| [ r, counts[r].to_i ] }
  end

  def choice_counts
    return {} unless choices?

    counts = answered.where.not(choice: nil).group(:choice).count
    choice_options.to_h { |option| [ option, counts[option].to_i ] }
  end

  # ── Pop-up ────────────────────────────────────────────────────────────

  # The one survey to show this member now, or nil. Not for brand-new
  # members (first day), nor anyone who answered, declined, is snoozed,
  # answered another survey this week,
  # has snoozed three times, or opted out.
  def self.prompt_for(user, now: Time.current)
    return nil unless user&.persisted?
    return nil if user.created_at > now - 1.day
    return nil if user.card_dismissed?(OPT_OUT_KEY)
    # One survey at a time: a rest after answering (or declining) one.
    recent = now - REST_BETWEEN_SURVEYS
    return nil if FeedbackResponse.where(user_id: user.id).where("submitted_at > ? OR declined_at > ?", recent, recent).exists?

    live.order(starts_at: :desc).limit(5).detect do |campaign|
      next false unless campaign.includes_user?(user, now: now)

      response = campaign.responses.find_by(user_id: user.id)
      response.nil? || response.promptable?(now: now)
    end
  rescue StandardError => e
    Rails.logger.warn("[feedback] prompt_for failed: #{e.class}: #{e.message}")
    nil
  end

  private

  def tidy_choices
    self.choice_options = Array(choice_options).map { |o| o.to_s.squish.first(120) }.compact_blank.uniq.first(MAX_CHOICES)
    self.follow_up_prompt = follow_up_prompt.to_s.squish.presence
    self.choice_question = choice_question.to_s.squish.presence
  end

  def tidy_questions
    list = Array(questions).filter_map do |q|
      q = q.to_h.stringify_keys
      kind = q["kind"].to_s.downcase
      next unless QUESTION_KINDS.include?(kind)

      tidy = { "kind" => kind, "text" => q["text"].to_s.squish.first(200) }
      tidy["hint"] = q["hint"].to_s.squish.first(200) if q["hint"].present?
      if %w[one many].include?(kind)
        tidy["options"] = Array(q["options"]).map { |o| o.to_s.squish.first(120) }.compact_blank.uniq
        tidy["max"] = q["max"].to_i if kind == "many" && q["max"].to_i.positive?
      end
      tidy["optional"] = true if q["optional"] && kind != "text"
      tidy
    end
    # Keys follow the order; the rating's answer is the rating column.
    number = 0
    self.questions = list.first(MAX_QUESTIONS).map do |q|
      q.merge("key" => (q["kind"] == "rating" ? "rating" : "q#{number += 1}"))
    end
  end

  def questions_complete
    Array(@question_errors).each { |message| errors.add(:questions, message) }
    return if questions.blank?

    errors.add(:questions, "can have only one rating") if questions.count { |q| q["kind"] == "rating" } > 1
    questions.each do |q|
      label = "“#{q['text'].to_s.first(40)}”"
      errors.add(:questions, "#{label} needs its question text") if q["text"].blank? && q["kind"] != "rating"
      next unless %w[one many].include?(q["kind"])

      errors.add(:questions, "#{label} needs at least two answers") if q["options"].size < 2
      errors.add(:questions, "#{label} has more than #{MAX_OPTIONS} answers") if q["options"].size > MAX_OPTIONS
    end
  end

  def ends_after_start
    return if ends_at.blank?

    errors.add(:ends_at, "must be after the start") if starts_at.present? && ends_at <= starts_at
    errors.add(:ends_at, "must be in the future") if new_record? && ends_at <= Time.current
  end

  def choices_complete
    return if choice_question.blank? && choice_options.empty?

    errors.add(:choice_options, "need at least two answers") if choice_question.present? && choice_options.size < 2
    errors.add(:choice_question, "is needed for the answers") if choice_question.blank? && choice_options.any?
  end
end

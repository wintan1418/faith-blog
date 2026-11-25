# frozen_string_literal: true

class BibleQuizQuestion < ApplicationRecord
  has_many :user_seen_quiz_questions, dependent: :delete_all
  # Players' "Report this question" reports, reviewed in Admin → Reports.
  has_many :reports, as: :reportable, dependent: :destroy

  # Why a player can report a question. Every reason but "other" also counts
  # as a flag, and RETIRE_AT flags take the question out of the pool until an
  # admin looks at it.
  REPORT_REASONS = {
    "wrong_answer"    => "Wrong answer",
    "unclear"         => "Unclear question",
    "wrong_reference" => "Not in the Bible / wrong reference",
    "off_theme"       => "Doesn't fit the theme",
    "other"           => "Other"
  }.freeze
  RETIRE_AT = 2

  validates :prompt, :correct_index, :fingerprint, presence: true
  validates :fingerprint, uniqueness: true
  validate  :choices_well_formed
  validate  :text_well_formed
  validate  :answer_not_given_away

  before_validation :set_fingerprint
  before_validation :set_content_keys

  scope :recent, -> { order(created_at: :desc) }
  scope :by_theme,      ->(theme)      { theme.present?      ? where(theme: theme)           : all }
  scope :by_difficulty, ->(difficulty) { difficulty.present? ? where(difficulty: difficulty) : all }
  scope :by_kind,       ->(kind)       { kind.present?       ? where(kind: kind)             : all }

  # Pull N random questions — preferring questions THIS USER hasn't seen in
  # the last 30 days. Falls back to least-recently-seen when the unseen
  # pool is exhausted so the round is never short. theme/difficulty/kind
  # are optional filters; pass nil/"" to sample across all.
  # Questions two players have flagged as wrong stop being served.
  scope :trusted, -> { where("flags_count < ?", RETIRE_AT) }

  # Pull N random questions for this user, on N different verses:
  #   1. questions on verses the user hasn't seen in the last 30 days
  #      (seeing any question on a verse counts as seeing that verse, so
  #      the next round doesn't ask about it again in other words);
  #   2. then questions they haven't seen, on verses they have;
  #   3. then the least-recently-seen questions,
  # so the round is only short when the pool has too few verses.
  # theme/difficulty/kind are optional filters (nil/"" samples across all);
  # exclude_ids are left out, and so are their verses.
  def self.sample_for(user:, theme: nil, difficulty: nil, kind: nil, count: 5, exclude_ids: [])
    candidates = trusted.by_theme(theme).by_difficulty(difficulty).by_kind(kind)
    candidates = candidates.where.not(id: exclude_ids) if exclude_ids.present?
    return [] if count <= 0 || candidates.none?

    seen_ids = UserSeenQuizQuestion
                .where(user_id: user.id)
                .where("last_seen_at >= ?", SEEN_WINDOW.ago)
                .pluck(:bible_quiz_question_id)
    seen_verses = where(id: seen_ids).where.not(verse_key: nil).distinct.pluck(:verse_key)
    taken = exclude_ids.present? ? where(id: exclude_ids).where.not(verse_key: nil).pluck(:verse_key).to_set : Set.new

    picked = []
    pick = lambda do |rows|
      rows.each do |row|
        break if picked.size >= count
        next if row.verse_key && taken.include?(row.verse_key)

        taken << row.verse_key if row.verse_key
        picked << row
      end
    end

    unseen = candidates.where.not(id: seen_ids)
    fresh_verses = seen_verses.any? ? unseen.where("verse_key IS NULL OR verse_key NOT IN (?)", seen_verses) : unseen
    pick.call(fresh_verses.order(Arel.sql("RANDOM()")).limit(count * 4))
    pick.call(unseen.where.not(id: picked.map(&:id)).order(Arel.sql("RANDOM()")).limit(count * 4)) if picked.size < count
    return picked if picked.size >= count

    # Top up with oldest-seen questions when the unseen pool runs dry.
    fill_ids = UserSeenQuizQuestion
                .where(user_id: user.id)
                .where(bible_quiz_question_id: candidates.select(:id))
                .order(last_seen_at: :asc)
                .limit((count - picked.size) * 6)
                .pluck(:bible_quiz_question_id)
    by_id = candidates.where(id: fill_ids).index_by(&:id)
    pick.call(fill_ids.filter_map { |id| by_id[id] })
    picked
  end

  SEEN_WINDOW = 30.days

  # Pool size the background top-up aims for, per theme × difficulty.
  POOL_TARGET = 40
  # Beyond this a filter only grows when we're short (see needs_top_up?);
  # stops a heavy player's "unseen" pressure from generating forever.
  POOL_CAP = 400

  # Build a round from the pool WITHOUT touching the AI. When the exact
  # theme/difficulty filter is short, drop the difficulty — but never the
  # theme: a player who picked "The Cross" gets only questions on the cross,
  # even if that makes the round shorter (quiz_generate says so and tops the
  # theme up). With no theme picked, any trusted question will do.
  # sample_for already falls back to least-recently-seen rows.
  def self.serve_round(user:, theme: nil, difficulty: nil, count: 5)
    widenings = [ [ theme, difficulty ], [ theme, nil ] ]
    widenings << [ nil, nil ] if theme.blank?

    rows = []
    widenings.uniq.each do |t, d|
      break if rows.size >= count

      rows += sample_for(user: user, theme: t, difficulty: d,
                         count: count - rows.size, exclude_ids: rows.map(&:id))
    end
    rows
  end

  def self.pool_size(theme: nil, difficulty: nil)
    trusted.by_theme(theme).by_difficulty(difficulty).count
  end

  # True when the filter's pool is below target, or this user has fewer
  # than two rounds' worth of unseen questions left in it.
  def self.needs_top_up?(user:, theme: nil, difficulty: nil, length: 5)
    size = pool_size(theme: theme, difficulty: difficulty)
    return true if size < POOL_TARGET
    return false if size >= POOL_CAP || user.nil?

    seen_ids = UserSeenQuizQuestion.where(user_id: user.id)
                                   .where("last_seen_at >= ?", 30.days.ago)
                                   .select(:bible_quiz_question_id)
    unseen = trusted.by_theme(theme).by_difficulty(difficulty).where.not(id: seen_ids).count
    unseen < length * 2
  end

  # Legacy entrypoint kept for any callers that don't have a user context.
  def self.sample(n = 5)
    order(Arel.sql("RANDOM()")).limit(n).to_a
  end

  # Record that the given user saw these questions right now.
  # Note: do NOT include :updated_at in update_only — Rails auto-appends
  # it on upsert and PG rejects 'SET updated_at = …, updated_at = …'.
  def self.mark_seen!(user:, question_ids:)
    return if question_ids.blank?

    now = Time.current
    rows = question_ids.uniq.map do |qid|
      { user_id: user.id, bible_quiz_question_id: qid, last_seen_at: now, created_at: now, updated_at: now }
    end
    UserSeenQuizQuestion.upsert_all(rows, unique_by: :idx_seen_user_q,
                                          update_only: [ :last_seen_at ])
  end

  # A player reports this question. One report per player per question:
  # reporting again updates their reason instead of counting twice.
  # Returns the Report.
  def report!(reporter:, reason:, note: nil)
    reason = REPORT_REASONS.key?(reason.to_s) ? reason.to_s : "wrong_answer"
    note = note.to_s.squish.truncate(300).presence
    text = [ "Quiz question: #{REPORT_REASONS[reason]}.", (note && "Note: #{note}") ].compact.join(" ")

    transaction do
      report = reports.pending.find_by(reporter: reporter)
      if report
        report.update!(reason: text)
      else
        report = reports.create!(reporter: reporter, reason: text)
        self.class.increment_counter(:flags_count, id) unless reason == "other"
      end
      report
    end
  end

  def retired?
    flags_count >= RETIRE_AT
  end

  # Admin: take the question out of the pool, or put it back after review.
  def retire!
    update_column(:flags_count, [ flags_count, RETIRE_AT ].max)
  end

  def restore!
    update_column(:flags_count, 0)
  end

  # Saves generated questions, skipping any the pool already has: same
  # prompt (fingerprint), or the same question in other words (a trusted row
  # with the same content_key — e.g. a sixth "what is the reference of
  # Philippians 4:13?").
  def self.import_from_generator!(questions)
    inserted = 0
    questions.each do |q|
      row = new(
        kind: q.kind.to_s,
        prompt: q.prompt,
        choices: q.choices,
        correct_index: q.correct_index,
        reference: q.reference,
        explanation: q.explanation,
        difficulty: q.respond_to?(:difficulty) ? q.difficulty.to_s : "medium",
        theme: q.respond_to?(:theme) ? q.theme.to_s : nil
      )
      row.valid? # sets the keys
      next if row.content_key.present? && trusted.exists?(content_key: row.content_key)

      inserted += 1 if row.save
    end
    inserted
  end

  # The verse a question is about, e.g. "philippians 4:13" (a range counts
  # as its first verse, so "Ephesians 2:8-9" and "Ephesians 2:8" are the
  # same verse). nil when the question has no reference.
  def compute_verse_key
    text = reference.to_s.strip
    return nil if text.blank?

    ref = Scripture::Reference.parse(text) || Scripture::Reference.find_all(text).first
    return self.class.normalize_text(text).presence&.truncate(80, omission: "") unless ref

    [ ref.book.ref_name, ref.chapter ].join(" ").downcase + (ref.verse_start ? ":#{ref.verse_start}" : "")
  end

  # What makes two questions "the same question": kind + verse, plus the
  # blanked word (fill_blank) or the true phrase (true_phrase). Questions
  # without a reference fall back to their exact prompt.
  def compute_content_key
    verse = compute_verse_key || "prompt:#{self.class.normalize_text(prompt)}"
    extra = %w[fill_blank true_phrase].include?(kind.to_s) ? self.class.normalize_text(correct_choice) : nil
    [ kind, verse, extra ].compact_blank.join("|").truncate(255, omission: "")
  end

  def correct_choice
    Array(choices)[correct_index.to_i].to_s
  end

  # Why the prompt gives its own answer away, or [] when it doesn't.
  #   reference   the prompt cites the verse ("Ephesians 2:8-9 emphasizes
  #               grace… What is the chapter:verse?") or contains the answer
  #   fill_blank  the blanked word is elsewhere in the prompt
  #   which_book  the prompt names the answer's book
  def giveaway_reasons
    answer = correct_choice.strip
    return [] if answer.blank? || prompt.blank?

    text = prompt.to_s
    norm = " #{self.class.normalize_text(text)} "
    case kind.to_s
    when "reference" then reference_giveaways(text, norm, answer)
    when "fill_blank"
      word = self.class.normalize_text(answer)
      blanked = " #{self.class.normalize_text(text.gsub(/_{2,}|\[\s*blank\s*\]/i, " "))} "
      word.present? && blanked.include?(" #{word} ") ? [ "the blanked word \"#{answer}\" is in the prompt" ] : []
    when "which_book" then book_giveaways(text, norm, answer)
    else []
    end
  end

  def self.normalize_text(text)
    text.to_s.downcase.unicode_normalize(:nfkd).gsub(/\p{Mn}/, "").gsub(/[’'`]/, "").gsub(/[^a-z0-9: ]+/, " ").gsub(/(?<!\d):|:(?!\d)/, " ").squish
  end

  private

  def set_fingerprint
    self.fingerprint = Digest::SHA1.hexdigest(prompt.to_s.downcase.strip) if fingerprint.blank? || (persisted? && prompt_changed?)
  end

  def set_content_keys
    self.verse_key = compute_verse_key
    self.content_key = compute_content_key
  end

  def answer_not_given_away
    giveaway_reasons.each { |reason| errors.add(:prompt, "gives the answer away: #{reason}") }
  end

  def reference_giveaways(text, norm, answer)
    reasons = []
    reasons << "it contains the answer \"#{answer}\"" if norm.match?(/(?<![1-3]) #{Regexp.escape(self.class.normalize_text(answer))} /)
    wanted = [ answer, reference ].filter_map { |r| Scripture::Reference.parse(r.to_s) || Scripture::Reference.find_all(r.to_s).first }
    cited = Scripture::Reference.find_all(text.gsub(/(\d):(?!\d)/, '\1 '))
    if wanted.any? { |w| cited.any? { |c| c.book == w.book && c.chapter == w.chapter && c.verse_start == w.verse_start } }
      reasons << "it cites the verse"
    end
    place = answer[/(\d+:\d+(?:\s*[-–]\s*\d+)?)\s*\z/, 1]
    if place && text.match?(/(?<![\d:])#{Regexp.escape(place.split(/\s*[-–]\s*/).first)}(?![\d])/)
      reasons << "it contains the chapter:verse #{place}"
    end
    reasons.uniq
  end

  # Books whose names are also people (John, James, Jude…) only give the
  # answer away when cited ("John 3:16", "the book of John", "John's gospel").
  def book_giveaways(text, norm, answer)
    book = Scripture::Canon.find(answer.sub(/\Athe\s+(?:book\s+of\s+)?/i, "").strip)
    names = book ? [ book.name, book.ref_name ].uniq : [ answer ]
    core = names.map { |n| n.sub(/\A[1-3]\s+/, "") }.uniq
    cited = Scripture::Reference.find_all(text.gsub(/(\d):(?!\d)/, '\1 ')).any? { |r| book && r.book == book }
    named = core.any? do |n|
      n_norm = self.class.normalize_text(n)
      norm.include?(" book of #{n_norm} ") || norm.match?(/ (?:[1-3] )?#{Regexp.escape(n_norm)} \d/) ||
        (!PERSON_BOOKS.include?(n_norm) && norm.include?(" #{n_norm} ")) ||
        norm.match?(/ #{Regexp.escape(n_norm)}s (?:gospel|letter|epistle|book)/)
    end
    cited || named ? [ "it names the book #{answer}" ] : []
  end

  # Book names that are also everyday names or words in prompts.
  PERSON_BOOKS = %w[
    joshua judges ruth samuel kings ezra nehemiah esther job isaiah jeremiah ezekiel daniel hosea joel amos
    obadiah jonah micah nahum habakkuk zephaniah haggai zechariah malachi matthew mark luke john acts timothy
    titus philemon james peter jude numbers hebrews revelation
  ].freeze

  # Guards against the AI's common slips: lettered options typed into the
  # question ("A) … B) …"), bare letters as choices, and reference
  # questions whose choices lack a book name ("1:2").
  LETTERED_OPTIONS = /(?:^|\s)[A-D]\)\s/
  REFERENCE_CHOICE = /[[:alpha:]]{2,}.*\d+:\d+/

  def text_well_formed
    errors.add(:prompt, "contains lettered options") if prompt.to_s.match?(LETTERED_OPTIONS)
    return unless choices.is_a?(Array)

    errors.add(:choices, "are bare letters") if choices.any? { |c| c.to_s.strip.match?(/\A[A-D]\.?\z/) }
    return unless kind.to_s == "reference"

    errors.add(:choices, "must be full references") unless choices.all? { |c| c.to_s.match?(REFERENCE_CHOICE) }
  end

  def choices_well_formed
    return errors.add(:choices, "must have exactly 4 entries") unless choices.is_a?(Array) && choices.size == 4
    errors.add(:correct_index, "out of range") unless correct_index.to_i.between?(0, 3)
  end
end

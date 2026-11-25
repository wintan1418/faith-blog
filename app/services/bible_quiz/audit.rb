# frozen_string_literal: true

# One-off (and re-runnable) clean-up of the Bible Quiz pool, behind
# `bin/rails bible_quiz:audit` (dry run) / `APPLY=1 bin/rails bible_quiz:audit`.
#
#   1. giveaways   reference / fill_blank / which_book questions whose prompt
#                  contains the answer (BibleQuizQuestion#giveaway_reasons)
#   2. phrases     true_phrase questions whose right answer isn't in the
#                  Bible, or whose decoys are (BibleQuiz::AnswerCheck); a
#                  clearly mismarked one is corrected instead
#   3. duplicates  questions with the same content_key: the best one stays
#                  (most played, fewest flags, oldest), the rest retire
#   4. explicit    ids passed in (questions players reported that the rules
#                  above may not catch)
#
# Questions are retired (BibleQuizQuestion#retire!), never deleted, so their
# reports and play history stay. Pending reports of a retired question are
# resolved. Only trusted (live) questions are looked at, so running it
# twice changes nothing the second time.
module BibleQuiz
  class Audit
    Summary = Struct.new(:keys_backfilled, :giveaways, :phrases_wrong, :phrases_fixed, :phrases_unchecked,
                         :duplicates, :duplicate_groups, :explicit, :reports_resolved, keyword_init: true) do
      def retired = giveaways + phrases_wrong + duplicates + explicit
    end

    NOTE = "Retired by bible_quiz:audit"

    def initialize(apply: false, retire_ids: [], out: $stdout, phrases: nil)
      @apply = apply
      @retire_ids = Array(retire_ids).map(&:to_i).uniq
      @out = out
      @phrases = phrases
      @retired = Set.new
      @summary = Summary.new(keys_backfilled: 0, giveaways: 0, phrases_wrong: 0, phrases_fixed: 0, phrases_unchecked: 0,
                             duplicates: 0, duplicate_groups: 0, explicit: 0, reports_resolved: 0)
    end

    def call
      backfill_keys
      audit_giveaways
      audit_phrases
      audit_explicit
      audit_duplicates
      resolve_reports
      @summary
    end

    private

    def live = BibleQuizQuestion.trusted.where.not(id: @retired.to_a)

    def backfill_keys
      BibleQuizQuestion.find_each do |q|
        verse, content = q.compute_verse_key, q.compute_content_key
        next if q.verse_key == verse && q.content_key == content

        @summary.keys_backfilled += 1
        # Dry run: keep the computed keys in memory for the duplicate pass.
        @keys ||= {}
        @keys[q.id] = content
        q.update_columns(verse_key: verse, content_key: content) if @apply
      end
    end

    def audit_giveaways
      live.where(kind: %w[reference fill_blank which_book]).find_each do |q|
        reasons = q.giveaway_reasons
        next if reasons.empty?

        @summary.giveaways += 1
        retire(q, "gives the answer away: #{reasons.join('; ')}")
      end
    end

    def audit_phrases
      phrases = @phrases || (PhraseCheck.available? ? PhraseCheck.new : nil)
      live.where(kind: "true_phrase").find_each do |q|
        result = phrases ? AnswerCheck.call(kind: q.kind, choices: q.choices, correct_index: q.correct_index,
                                            reference: q.reference, phrases: phrases) : nil
        case result&.status
        when :wrong
          @summary.phrases_wrong += 1
          retire(q, "true_phrase: #{phrase_problem(q, phrases)}")
        when :fixed
          @summary.phrases_fixed += 1
          @out.puts "  fix     ##{q.id} true_phrase: right answer is #{q.choices[result.correct_index].inspect}"
          q.update_columns(correct_index: result.correct_index, updated_at: Time.current) if @apply
        when :ok
          nil
        else
          @summary.phrases_unchecked += 1
        end
      end
      @out.puts "  (Bible text not loaded — true_phrase questions not checked)" unless phrases
    end

    def phrase_problem(q, phrases)
      decoys = q.choices.each_with_index.filter_map do |c, i|
        next if i == q.correct_index

        m = phrases.match(c)
        m && "decoy #{c.inspect} is #{Scripture::Canon[m.book]&.name} #{m.chapter}:#{m.verse} (#{m.translation.upcase})"
      end
      decoys << "answer #{q.choices[q.correct_index].inspect} not found in the Bible" unless phrases.biblical?(q.choices[q.correct_index])
      decoys.join("; ")
    end

    def audit_explicit
      live.where(id: @retire_ids).find_each do |q|
        @summary.explicit += 1
        retire(q, "listed for retirement")
      end
    end

    def audit_duplicates
      rows = live.pluck(:id, :content_key, :flags_count, :created_at)
      plays = UserSeenQuizQuestion.where(bible_quiz_question_id: rows.map(&:first)).group(:bible_quiz_question_id).count
      groups = rows.group_by { |id, key, *| (@keys && @keys[id]) || key }.reject { |key, g| key.blank? || g.size < 2 }
      groups.each do |key, group|
        @summary.duplicate_groups += 1
        keep = group.min_by { |id, _, flags, created| [ -plays.fetch(id, 0), flags, created, id ] }
        (group - [ keep ]).each do |id, *|
          @summary.duplicates += 1
          retire(BibleQuizQuestion.find(id), "duplicate of ##{keep.first} (#{key})")
        end
      end
    end

    def resolve_reports
      return if @retired.empty?

      pending = Report.pending.where(reportable_type: "BibleQuizQuestion", reportable_id: @retired.to_a)
      @summary.reports_resolved = pending.count
      return unless @apply

      pending.update_all(status: Report.statuses[:resolved], reviewed_at: Time.current, resolution_notes: NOTE, updated_at: Time.current)
    end

    def retire(q, why)
      @retired << q.id
      @out.puts "  retire  ##{q.id} #{q.kind} #{q.reference}: #{why}"
      q.retire! if @apply
    end
  end
end

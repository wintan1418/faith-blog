# frozen_string_literal: true

# Checks a quiz question's marked answer against the Bible before players
# see it. The question writer sometimes marks the wrong choice — e.g.
# "evil ______ corrupt good manners" (1 Corinthians 15:33) marked
# "companions" when the KJV says "communications".
#
#   fill_blank  the marked word must be in the KJV text of the reference
#   reference   the marked "chapter:verse" must be the reference's
#   which_book  the marked book must be the reference's book
#
# If exactly one other choice is the right one, the answer is corrected
# (:fixed); if none or several fit, the question is :wrong; kinds we can't
# check, or a lookup that failed, are :unknown.
module BibleQuiz
  class AnswerCheck
    Result = Data.define(:status, :correct_index)
    CHECKED_KINDS = %w[fill_blank reference which_book].freeze

    def self.call(kind:, choices:, correct_index:, reference:, lookup: ScriptureLookup)
      new(kind:, choices:, correct_index:, reference:, lookup:).call
    end

    def initialize(kind:, choices:, correct_index:, reference:, lookup:)
      @kind = kind.to_s
      @choices = Array(choices).map(&:to_s)
      @correct = correct_index.to_i
      @reference = reference.to_s.strip
      @lookup = lookup
    end

    def call
      return unknown unless CHECKED_KINDS.include?(@kind) && @reference.present?

      hits = case @kind
      when "fill_blank" then fill_blank_hits
      when "reference" then reference_hits
      when "which_book" then book_hits
      end
      return unknown if hits.nil?
      return Result.new(status: :ok, correct_index: @correct) if hits.include?(@correct)
      return Result.new(status: :fixed, correct_index: hits.first) if hits.size == 1

      Result.new(status: :wrong, correct_index: @correct)
    end

    private

    def unknown = Result.new(status: :unknown, correct_index: @correct)

    def fill_blank_hits
      text = @lookup.lookup(@reference)&.dig(:text)
      return nil if text.blank?

      words = " #{normalize(text)} "
      @choices.each_index.select { |i| (w = normalize(@choices[i])).present? && words.include?(" #{w} ") }
    end

    def reference_hits
      place = @reference[/(\d+:\d+)\s*\z/, 1] or return nil
      @choices.each_index.select { |i| @choices[i].strip.end_with?(place) && @choices[i][/(\d+:\d+)\s*\z/, 1] == place }
    end

    def book_hits
      book = normalize(@reference.sub(/\s*\d+(:\d+(-\d+)?)?\s*\z/, ""))
      return nil if book.blank?

      @choices.each_index.select { |i| normalize(@choices[i].sub(/\Athe\s+(book\s+of\s+)?/i, "")) == book }
    end

    def normalize(s)
      s.to_s.downcase.gsub(/[’']/, "").gsub(/[^a-z0-9 ]+/, " ").squish
    end
  end
end

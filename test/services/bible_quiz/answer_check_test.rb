# frozen_string_literal: true

require "test_helper"

class BibleQuiz::AnswerCheckTest < ActiveSupport::TestCase
  KJV = {
    "1 Corinthians 15:33" => "Be not deceived: evil communications corrupt good manners.",
    "John 11:35" => "Jesus wept."
  }.freeze
  Lookup = Struct.new(:texts) do
    def lookup(ref) = (t = texts[ref]) && { text: t }
  end

  def check(**args) = BibleQuiz::AnswerCheck.call(lookup: Lookup.new(KJV), **args)

  test "fill_blank: a wrongly marked answer is corrected to the word in the KJV" do
    r = check(kind: "fill_blank", choices: %w[communications companions thoughts actions], correct_index: 1,
              reference: "1 Corinthians 15:33")
    assert_equal :fixed, r.status
    assert_equal 0, r.correct_index
  end

  test "fill_blank: the right answer passes; none fitting is wrong; no text is unknown" do
    assert_equal :ok, check(kind: "fill_blank", choices: %w[laughed wept slept spoke], correct_index: 1, reference: "John 11:35").status
    assert_equal :wrong, check(kind: "fill_blank", choices: %w[a b c d], correct_index: 1, reference: "John 11:35").status
    assert_equal :unknown, check(kind: "fill_blank", choices: %w[a b c d], correct_index: 1, reference: "Jude 1:99").status
  end

  test "reference and which_book are checked against the reference itself" do
    r = check(kind: "reference", choices: [ "1:10", "11:23", "15:1", "12:4" ], correct_index: 2, reference: "1 Corinthians 11:23")
    assert_equal [ :fixed, 1 ], [ r.status, r.correct_index ]
    assert_equal :ok, check(kind: "which_book", choices: [ "Romans", "1 Corinthians", "Galatians", "Acts" ], correct_index: 1,
                            reference: "1 Corinthians 1:27").status
    assert_equal :unknown, check(kind: "what_does", choices: %w[a b c d], correct_index: 0, reference: "John 3:16").status
  end
end

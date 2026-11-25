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

  # Report #1074: "All options are phrases in the Bible".
  test "true_phrase: a decoy that is real Scripture (any translation) makes the question wrong" do
    extend BibleTextFixture
    seed_bible_text
    r = check(kind: "true_phrase", reference: "",
              choices: [ "Pray without ceasing.", "Faith without works is dead.", "Bear ye one another's burdens.",
                         "Love covers a multitude of sins." ], correct_index: 0)
    assert_equal :wrong, r.status
  end

  test "true_phrase: one real phrase and three non-biblical sayings pass; a mismarked one is fixed" do
    extend BibleTextFixture
    seed_bible_text
    choices = [ "God helps those who help themselves", "Pray without ceasing.", "Cleanliness is next to godliness",
                "This too shall pass" ]
    assert_equal :ok, check(kind: "true_phrase", reference: "1 Thessalonians 5:17", choices: choices, correct_index: 1).status
    r = check(kind: "true_phrase", reference: nil, choices: choices, correct_index: 0)
    assert_equal [ :fixed, 1 ], [ r.status, r.correct_index ]
    assert_equal :wrong, check(kind: "true_phrase", reference: nil, choices: choices.values_at(0, 2, 3) + [ "Let go and let God" ],
                               correct_index: 0).status
  end

  test "true_phrase is unknown when the Bible text isn't loaded" do
    assert_equal :unknown, check(kind: "true_phrase", reference: nil, choices: %w[a b c d], correct_index: 0).status
  end
end

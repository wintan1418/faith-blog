# frozen_string_literal: true

require "test_helper"

class BibleQuiz::PhraseCheckTest < ActiveSupport::TestCase
  include BibleTextFixture

  setup do
    seed_bible_text
    @check = BibleQuiz::PhraseCheck.new
  end

  test "real Scripture matches in any translation, normalized" do
    assert @check.biblical?("Pray without ceasing.")
    assert @check.biblical?("Bear ye one another's burdens.")
    m = @check.match("Love covers a multitude of sins.")
    assert m, "1 Peter 4:8 (WEB wording)"
    assert_equal [ 60, 4, 8 ], [ m.book, m.chapter, m.verse ]
    assert_not_equal "kjv", m.translation
    assert @check.biblical?("I can do all things through Christ which strengtheneth me")
  end

  test "close wording still matches (about 85% of the words, in order)" do
    assert @check.biblical?("Faith without works is dead.") # James 2:20 KJV, contained
    assert @check.biblical?("I can do all things through Christ who strengthens me!") # punctuation / -eth
  end

  test "popular sayings that aren't in the Bible don't match" do
    [ "God helps those who help themselves", "Cleanliness is next to godliness", "This too shall pass",
      "Spare the rod, spoil the child", "Charity begins at home" ].each do |saying|
      assert_not @check.biblical?(saying), saying
    end
  end

  test "a misquote that only trims a verse is still inside it" do
    assert @check.biblical?("Money is the root of all evil")
  end

  test "available? only when the verse text is loaded" do
    assert BibleQuiz::PhraseCheck.available?
    ScriptureVerse.delete_all
    assert_not BibleQuiz::PhraseCheck.available?
  end
end

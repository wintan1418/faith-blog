# frozen_string_literal: true

require "test_helper"

class BibleQuizQuestionTest < ActiveSupport::TestCase
  def build(**attrs)
    BibleQuizQuestion.new({ kind: "what_does", prompt: "What does 'justified by faith' mean?",
                            choices: [ "Saved by works", "Declared righteous", "Condemned", "Forgotten" ],
                            correct_index: 1, difficulty: "easy" }.merge(attrs))
  end

  test "a clean question is valid" do
    assert build.valid?
  end

  test "rejects lettered options typed into the question" do
    question = build(prompt: "What does it mean? A) Saved by works B) Declared righteous")
    assert_not question.valid?
    assert question.errors[:prompt].any?
  end

  test "rejects bare letters as choices" do
    assert_not build(choices: %w[C D B A]).valid?
  end

  test "reference questions need full references" do
    assert_not build(kind: "reference", choices: [ "1:2", "John 3:16", "Romans 3:23", "Acts 2:38" ]).valid?
    assert build(kind: "reference", choices: [ "1 John 2:25", "John 3:16", "Romans 3:23", "Acts 2:38" ]).valid?
  end
end

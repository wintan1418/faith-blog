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

  # Trello #102: a theme's round never borrows from other themes.
  test "serve_round keeps to the theme, widening only the difficulty" do
    user = User.create!(username: "bqq_player", email: "bqq_player@example.com", password: SecureRandom.base58(16))
    cross = Array.new(2) { |i| build(prompt: "Cross #{i}?", theme: "the_cross", difficulty: "hard").tap(&:save!) }
    Array.new(8) { |i| build(prompt: "Faith #{i}?", theme: "faith").tap(&:save!) }

    rows = BibleQuizQuestion.serve_round(user: user, theme: "the_cross", difficulty: "easy", count: 5)
    assert_equal cross.map(&:id).sort, rows.map(&:id).sort

    assert_equal 5, BibleQuizQuestion.serve_round(user: user, count: 5).size, "no theme: anything goes"
  end
end

# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Player reports #937 (prompt held the answer) and #1074 (every true_phrase
# choice was real Scripture).
class Ai::Bible::QuizGeneratorQualityTest < ActiveSupport::TestCase
  include BibleTextFixture

  test "the system prompt forbids giving the answer away and asks for non-biblical decoys" do
    prompt = Ai::Bible::QuizGenerator::SYSTEM_PROMPT
    assert_includes prompt, "NEVER GIVE THE ANSWER AWAY"
    assert_includes prompt, "Do NOT write the book,"
    assert_includes prompt, "must not appear anywhere else"
    assert_includes prompt, "must NOT be in the Bible in ANY translation"
    assert_includes prompt, "God helps those who help themselves"
    assert_includes prompt, "each must be about a DIFFERENT verse"
  end

  test "a true_phrase question whose decoys are Scripture is dropped" do
    seed_bible_text
    tp = lambda do |choices|
      { "kind" => "true_phrase", "prompt" => "Which of these does the Bible say?", "choices" => choices, "correct_index" => 0,
        "reference" => "1 Thessalonians 5:17", "explanation" => "KJV", "theme_link" => "prayer" }
    end
    reply = { "content" => [ { "type" => "text", "text" => { "questions" => [
      tp.call([ "Pray without ceasing.", "Faith without works is dead.", "Bear ye one another's burdens.",
                "Love covers a multitude of sins." ]),
      tp.call([ "Pray without ceasing.", "God helps those who help themselves", "This too shall pass",
                "Cleanliness is next to godliness" ])
    ] }.to_json } ] }

    questions = Ai::Moderation::Client.stub(:call, reply) { Ai::Bible::QuizGenerator.call(theme: "prayer") }
    assert_equal 1, questions.size
    assert_includes questions.first.choices, "God helps those who help themselves"
    assert_equal "Pray without ceasing.", questions.first.choices[questions.first.correct_index]
  end
end

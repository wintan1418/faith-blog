# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Character Match must return 5 distinct questions per round, ordered
# easy → hard. The old implementation filtered the quiz pool by a
# "character" kind nothing ever generated, so it repeated one stale
# question after several wasted AI calls.
class CharacterMatchRoundTest < ActionDispatch::IntegrationTest
  AI_RESPONSE = {
    "content" => [ {
      "type" => "text",
      "text" => {
        questions: [
          { prompt: "Q-hard: he was a lesser-known scribe.", choices: %w[Ezra Nathan Baruch Shaphan],
            correct_index: 2, difficulty: "hard", reference: "Jeremiah 36", explanation: "Jeremiah's scribe." },
          { prompt: "Q-easy-1: he built an ark before the flood.", choices: %w[Noah Moses Enoch Lot],
            correct_index: 0, difficulty: "easy", reference: "Genesis 6-9", explanation: "Walked with God." },
          { prompt: "Q-medium-1: she hid the spies in Jericho.", choices: %w[Ruth Rahab Deborah Jael],
            correct_index: 1, difficulty: "medium", reference: "Joshua 2", explanation: "Woman of faith." },
          { prompt: "Q-easy-2: shepherd boy who felled a giant.", choices: %w[Saul David Jonathan Samuel],
            correct_index: 1, difficulty: "easy", reference: "1 Samuel 17", explanation: "Man after God's heart." },
          { prompt: "Q-medium-2: he doubted until he touched.", choices: %w[Peter Thomas Philip Andrew],
            correct_index: 1, difficulty: "medium", reference: "John 20", explanation: "Believed on seeing." }
        ]
      }.to_json
    } ]
  }.freeze

  setup do
    @user = User.create!(username: "cm_player", email: "cm_player@example.com",
                         password: "password123", password_confirmation: "password123")
    sign_in @user
  end

  test "a round returns 5 distinct questions ordered easy to hard" do
    Ai::Moderation::Client.stub :call, AI_RESPONSE do
      post games_character_match_generate_path, as: :json
    end

    assert_response :success
    payload = JSON.parse(response.body)
    assert payload["ok"]

    questions = payload["questions"]
    assert_equal 5, questions.size
    assert_equal 5, questions.map { |q| q["prompt"] }.uniq.size, "questions must not repeat"
    assert_equal %w[easy easy medium medium hard], questions.map { |q| q["difficulty"] }

    questions.each do |q|
      assert_equal "character", q["kind"]
      assert_equal 4, q["choices"].size
      assert_includes 0..3, q["correct_index"]
    end
  end

  test "the shuffled correct_index still points at the right answer" do
    Ai::Moderation::Client.stub :call, AI_RESPONSE do
      post games_character_match_generate_path, as: :json
    end

    payload = JSON.parse(response.body)
    noah = payload["questions"].find { |q| q["prompt"].start_with?("Q-easy-1") }
    assert_equal "Noah", noah["choices"][noah["correct_index"]]
  end

  test "an AI failure returns a friendly error instead of hanging" do
    raiser = ->(**) { raise Ai::Bible::CharacterMatchRound::ParseError, "no valid questions" }
    Ai::Bible::CharacterMatchRound.stub :call, raiser do
      post games_character_match_generate_path, as: :json
    end

    assert_response :bad_gateway
    payload = JSON.parse(response.body)
    refute payload["ok"]
    assert_match(/try again/i, payload["error"])
  end
end

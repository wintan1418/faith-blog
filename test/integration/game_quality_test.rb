# frozen_string_literal: true

require "test_helper"

# Games quality features: players can flag wrong questions (two flags
# retire a question from the pool), and game results can be shared to
# the feed via the composer prefill.
class GameQualityTest < ActionDispatch::IntegrationTest
  setup do
    @player = User.create!(username: "gq_player", email: "gq_player@example.com",
                           password: "password123", password_confirmation: "password123")
    @question = BibleQuizQuestion.create!(
      kind: "which_book", prompt: "Who is our peace, having broken down the middle wall of partition?",
      choices: [ "Ephesians", "Romans", "Galatians", "Hebrews" ],
      correct_index: 0, reference: "Ephesians 2:14", explanation: "KJV Eph 2:14",
      theme: "the_cross", difficulty: "medium"
    )
    sign_in @player
  end

  test "flagging a question twice retires it from the pool" do
    post games_quiz_flag_path, params: { question_id: @question.id }, as: :json
    assert_response :success
    assert_equal 1, @question.reload.flags_count
    assert_includes BibleQuizQuestion.trusted, @question

    post games_quiz_flag_path, params: { question_id: @question.id }, as: :json
    assert_equal 2, @question.reload.flags_count
    refute_includes BibleQuizQuestion.trusted, @question
    assert_empty BibleQuizQuestion.sample_for(user: @player, count: 5)
  end

  test "flagging an unknown question 404s cleanly" do
    post games_quiz_flag_path, params: { question_id: 999_999 }, as: :json
    assert_response :not_found
  end

  test "quiz rounds include question ids so the client can flag them" do
    post games_quiz_generate_path, params: { length: 5 }, as: :json
    payload = JSON.parse(response.body)
    assert payload["ok"]
    assert_equal @question.id, payload["questions"].first["id"]
  end

  test "the composer prefills a shared game result as plain text" do
    get new_post_path(prefill: "🎮 I just scored 5/5 (100%) on Character Match. <script>alert(1)</script>")

    assert_response :success
    assert_match "I just scored 5/5", response.body
    assert_no_match "<script>alert(1)</script>", response.body
  end
end

# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

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

  test "a 10-question round tops the pool up with several batches" do
    batch_num = 0
    fake_batch = lambda do |**|
      batch_num += 1
      Array.new(5) do |i|
        Ai::Bible::QuizGenerator::Question.new(
          kind: "which_book", prompt: "Batch #{batch_num} question #{i} of the round?",
          choices: %w[Romans Acts John Jude], correct_index: 0,
          reference: "Romans 1:1", explanation: "KJV", theme: "faith", difficulty: "easy"
        )
      end
    end

    Ai::Bible::QuizGenerator.stub :call, fake_batch do
      post games_quiz_generate_path, params: { length: 10 }, as: :json
    end

    payload = JSON.parse(response.body)
    assert payload["ok"]
    assert_equal 10, payload["questions"].size, "long rounds must fill from multiple batches"
  end

  test "the composer prefills a shared game result as plain text" do
    get new_post_path(prefill: "I finished a round. <script>alert(1)</script>")

    assert_response :success
    assert_match "I finished a round.", response.body
    assert_no_match "<script>alert(1)</script>", response.body
  end

  test "a game share builds a card with a warm, non-competitive line" do
    get new_post_path(share_game: "character_match", score: 4, total: 5, streak: 3, secs: 38)

    assert_response :success
    assert_match "Come play with me", response.body
    assert_match "Sharing your", response.body
    assert_no_match(/beat me/i, response.body)
  end

  test "an unknown share_game slug is ignored" do
    get new_post_path(share_game: "poker", score: 4, total: 5)
    assert_response :success
    assert_no_match "Sharing your", response.body
  end

  test "creating a shared post persists the sanitized game card and renders it" do
    room = Room.create!(name: "GQ Room", description: "x")
    post posts_path, params: { post: {
      content: "Come play with me. 🙌", room_id: room.id, status: "published",
      game_share: { slug: "quiz", score: "99", total: "5", streak: "2", secs: "40" }.to_json
    } }

    created = Post.order(:created_at).last
    assert_equal "quiz", created.game_share["slug"]
    assert_equal 5, created.game_share["score"], "score must be clamped to total"

    get post_path(created)
    assert_response :success
    assert_match "Play Bible Quiz", response.body
    assert_match "/games/quiz", response.body
  end
end

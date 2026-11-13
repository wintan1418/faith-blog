# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Trello QA: "Bible Quiz takes over 30 seconds to load questions". The
# round used to block on up to 5 synchronous AI batches whenever the
# theme/difficulty pool was thin. Rounds are now served from the pool and
# the pool grows in BibleQuizTopUpJob.
class BibleQuizGenerateTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  NO_AI = ->(**) { raise "quiz_generate must not call the AI here" }

  setup do
    @player = User.create!(username: "bq_player", email: "bq_player@example.com",
                           password: "password123", password_confirmation: "password123")
    sign_in @player
  end

  def make_questions(count, theme:, difficulty:)
    Array.new(count) do |i|
      BibleQuizQuestion.create!(
        kind: "which_book", prompt: "#{theme} #{difficulty} question #{i} #{SecureRandom.hex(3)}?",
        choices: %w[Romans Acts John Jude], correct_index: 0,
        reference: "Romans 1:1", explanation: "KJV", theme: theme, difficulty: difficulty
      )
    end
  end

  def generate(**params)
    post games_quiz_generate_path, params: params, as: :json
    JSON.parse(response.body)
  end

  test "a well-stocked pool is served without calling the AI or enqueuing a top-up" do
    make_questions(BibleQuizQuestion::POOL_TARGET, theme: "faith", difficulty: "easy")

    payload = nil
    Ai::Bible::QuizGenerator.stub :call, NO_AI do
      assert_no_enqueued_jobs(only: BibleQuizTopUpJob) do
        payload = generate(theme: "faith", difficulty: "easy", length: 10)
      end
    end

    assert payload["ok"]
    assert_equal 10, payload["questions"].size
    assert(payload["questions"].all? { |q| q["theme"] == "faith" && q["difficulty"] == "easy" })
    assert_equal "faith", payload["theme"]
  end

  test "a short pool returns what exists immediately and enqueues a background top-up" do
    make_questions(3, theme: "grace", difficulty: "hard")

    payload = nil
    Ai::Bible::QuizGenerator.stub :call, NO_AI do
      assert_enqueued_with(job: BibleQuizTopUpJob, args: [ "grace", "hard", BibleQuizTopUpJob::DEFAULT_BATCHES ]) do
        payload = generate(theme: "grace", difficulty: "hard", length: 10)
      end
    end

    assert payload["ok"]
    assert_equal 3, payload["questions"].size
  end

  test "a short filter widens to other difficulties, then other themes" do
    exact = make_questions(2, theme: "prayer", difficulty: "easy")
    same_theme = make_questions(2, theme: "prayer", difficulty: "hard")
    other = make_questions(6, theme: "holiness", difficulty: "medium")

    payload = Ai::Bible::QuizGenerator.stub(:call, NO_AI) { generate(theme: "prayer", difficulty: "easy", length: 5) }

    ids = payload["questions"].map { |q| q["id"] }
    assert_equal 5, ids.size
    assert_equal ids.uniq, ids, "no duplicates across widening steps"
    assert_empty exact.map(&:id) - ids, "exact-filter questions come first"
    assert_empty same_theme.map(&:id) - ids, "then the same theme at any difficulty"
    assert_equal 1, (ids & other.map(&:id)).size
  end

  test "an empty pool makes at most one synchronous AI call" do
    calls = 0
    fake = lambda do |**|
      calls += 1
      Array.new(5) do |i|
        Ai::Bible::QuizGenerator::Question.new(
          kind: "which_book", prompt: "Fresh question #{i} #{SecureRandom.hex(3)}?",
          choices: %w[Romans Acts John Jude], correct_index: 0,
          reference: "Romans 1:1", explanation: "KJV", theme: "faith", difficulty: "easy"
        )
      end
    end

    payload = nil
    Ai::Moderation::Client.stub :stub?, false do
      Ai::Bible::QuizGenerator.stub :call, fake do
        payload = generate(theme: "faith", difficulty: "easy", length: 20)
      end
    end

    assert_equal 1, calls
    assert payload["ok"]
    assert_equal 5, payload["questions"].size
  end

  test "an empty pool with a failing AI still answers with no questions" do
    payload = nil
    Ai::Moderation::Client.stub :stub?, false do
      Ai::Bible::QuizGenerator.stub :call, ->(**) { raise Ai::Moderation::Client::ApiError, "timeout" } do
        payload = generate(length: 5)
      end
    end

    assert payload["ok"]
    assert_empty payload["questions"]
  end

  test "the top-up enqueue is guarded against stampedes" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    assert BibleQuizTopUpJob.enqueue_once(theme: "faith", difficulty: "easy")
    refute BibleQuizTopUpJob.enqueue_once(theme: "faith", difficulty: "easy")
    assert BibleQuizTopUpJob.enqueue_once(theme: "faith", difficulty: "hard")
    assert_enqueued_jobs 2, only: BibleQuizTopUpJob
  ensure
    Rails.cache = original
  end
end

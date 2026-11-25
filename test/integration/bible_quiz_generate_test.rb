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

  # Each question on its own verse: a round never repeats a verse.
  def next_reference
    @ref_seq = (@ref_seq || 0) + 1
    "Psalm #{@ref_seq}:1"
  end

  def make_questions(count, theme:, difficulty:)
    Array.new(count) do |i|
      BibleQuizQuestion.create!(
        kind: "which_book", prompt: "#{theme} #{difficulty} question #{i} #{SecureRandom.random_number(10**6).to_s.rjust(6, "0")}?",
        choices: %w[Romans Acts John Jude], correct_index: 0,
        reference: next_reference, explanation: "KJV", theme: theme, difficulty: difficulty
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

  test "a short filter widens to other difficulties, never other themes" do
    exact = make_questions(2, theme: "prayer", difficulty: "easy")
    same_theme = make_questions(2, theme: "prayer", difficulty: "hard")
    make_questions(6, theme: "holiness", difficulty: "medium")

    payload = Ai::Bible::QuizGenerator.stub(:call, NO_AI) { generate(theme: "prayer", difficulty: "easy", length: 5) }

    ids = payload["questions"].map { |q| q["id"] }
    assert_equal ids.uniq, ids, "no duplicates across widening steps"
    assert_equal (exact + same_theme).map(&:id).sort, ids.sort, "only prayer questions, exact filter first"
    assert_equal exact.map(&:id).sort, ids.first(2).sort
    assert(payload["questions"].all? { |q| q["theme"] == "prayer" })
    assert_equal "Only 4 questions on Prayer so far. More are being written, so play again soon for a full round.", payload["notice"]
  end

  # Trello #102: "I picked The Cross and got unrelated questions."
  test "a theme only ever yields questions on that theme" do
    cross = make_questions(3, theme: "the_cross", difficulty: "medium")
    %w[faith grace prayer bible_history].each { |other| make_questions(15, theme: other, difficulty: "medium") }

    [ 5, 10, 20 ].each do |length|
      [ nil, "medium", "easy" ].each do |difficulty|
        payload = Ai::Bible::QuizGenerator.stub(:call, NO_AI) { generate(theme: "the_cross", difficulty: difficulty, length: length) }
        assert payload["ok"]
        themes = payload["questions"].map { |q| q["theme"] }.uniq
        assert_equal [ "the_cross" ], themes, "length #{length}, difficulty #{difficulty.inspect}"
        assert_equal cross.map(&:id).sort, payload["questions"].map { |q| q["id"] }.sort
        assert_match(/Only 3 questions on The Cross so far/, payload["notice"])
      end
    end
  end

  test "a full themed round has no notice" do
    make_questions(5, theme: "the_cross", difficulty: "easy")
    payload = Ai::Bible::QuizGenerator.stub(:call, NO_AI) { generate(theme: "the_cross", difficulty: "easy", length: 5) }
    assert_equal 5, payload["questions"].size
    assert_nil payload["notice"]
  end

  test "a theme with no questions yet says so instead of serving other themes" do
    make_questions(10, theme: "faith", difficulty: "easy")
    payload = Ai::Bible::QuizGenerator.stub(:call, NO_AI) { generate(theme: "the_cross", length: 5) }

    refute payload["ok"]
    assert_nil payload["questions"]
    assert_equal "We're still writing questions on The Cross. Try again in a minute, or pick another theme.", payload["error"]
  end

  test "an empty theme is written on that theme, on the spot, when the AI is available" do
    make_questions(10, theme: "faith", difficulty: "easy")
    asked = []
    fake = lambda do |theme:, difficulty:|
      asked << theme
      Array.new(5) do |i|
        Ai::Bible::QuizGenerator::Question.new(
          kind: "what_does", prompt: "Cross question #{i} #{SecureRandom.random_number(10**6).to_s.rjust(6, "0")}?",
          choices: %w[Atonement Exile Famine Jubilee], correct_index: 0,
          reference: next_reference, explanation: "KJV", theme: theme, difficulty: difficulty || "medium"
        )
      end
    end

    payload = nil
    Ai::Moderation::Client.stub :stub?, false do
      Ai::Bible::QuizGenerator.stub(:call, fake) { payload = generate(theme: "the_cross", length: 5) }
    end

    assert_equal [ "the_cross" ], asked
    assert payload["ok"]
    assert_equal 5, payload["questions"].size
    assert(payload["questions"].all? { |q| q["theme"] == "the_cross" })
  end

  test "with no theme picked, a round still draws on every theme" do
    make_questions(2, theme: "faith", difficulty: "easy")
    make_questions(3, theme: "grace", difficulty: "hard")
    payload = Ai::Bible::QuizGenerator.stub(:call, NO_AI) { generate(length: 5) }
    assert_equal 5, payload["questions"].size
    assert_equal %w[faith grace], payload["questions"].map { |q| q["theme"] }.uniq.sort
    assert_nil payload["notice"]
  end

  test "an empty pool makes at most one synchronous AI call" do
    calls = 0
    fake = lambda do |**|
      calls += 1
      Array.new(5) do |i|
        Ai::Bible::QuizGenerator::Question.new(
          kind: "which_book", prompt: "Fresh question #{i} #{SecureRandom.random_number(10**6).to_s.rjust(6, "0")}?",
          choices: %w[Romans Acts John Jude], correct_index: 0,
          reference: next_reference, explanation: "KJV", theme: "faith", difficulty: "easy"
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

# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class BibleQuizTopUpJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def counting_generator
    calls = 0
    gen = lambda do |**|
      calls += 1
      yield calls if block_given?
      Array.new(5) do |i|
        Ai::Bible::QuizGenerator::Question.new(
          kind: "which_book", prompt: "Top-up question #{i} #{SecureRandom.hex(4)}?",
          choices: %w[Romans Acts John Jude], correct_index: 0,
          reference: "Romans 1:1", explanation: "KJV", theme: "faith", difficulty: "easy"
        )
      end
    end
    [ gen, -> { calls } ]
  end

  def with_ai(generator, &block)
    Ai::Moderation::Client.stub(:stub?, false) do
      Ai::Bible::QuizGenerator.stub(:call, generator, &block)
    end
  end

  test "imports generated batches into the pool" do
    gen, calls = counting_generator
    inserted = with_ai(gen) { BibleQuizTopUpJob.perform_now("faith", "easy", 3) }

    assert_equal 3, calls.call
    assert_equal 15, inserted
    assert_equal 15, BibleQuizQuestion.pool_size(theme: "faith", difficulty: "easy")
  end

  test "stops early once the pool reaches the target" do
    gen, calls = counting_generator
    with_ai(gen) { BibleQuizTopUpJob.perform_now("faith", "easy", 10, 8) }

    assert_equal 2, calls.call
  end

  test "survives generator errors and keeps going" do
    gen, = counting_generator { |n| raise Ai::Bible::QuizGenerator::ParseError, "bad json" if n == 1 }
    inserted = with_ai(gen) { BibleQuizTopUpJob.perform_now("faith", "easy", 2) }

    assert_equal 5, inserted
  end

  test "skips quietly when the AI is not configured" do
    Ai::Moderation::Client.stub :stub?, true do
      Ai::Bible::QuizGenerator.stub :call, ->(**) { flunk "must not call the AI" } do
        assert_equal 0, BibleQuizTopUpJob.perform_now("faith", "easy")
      end
    end
  end

  test "warm pool enqueues a top-up for each short theme × difficulty" do
    expected = Ai::Bible::QuizGenerator::THEMES.size * Ai::Bible::QuizGenerator::DIFFICULTIES.size
    Ai::Moderation::Client.stub :stub?, false do
      BibleQuizWarmPoolJob.perform_now
    end
    assert_enqueued_jobs expected, only: BibleQuizTopUpJob
  end
end

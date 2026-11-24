# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class ScriptureInsightJobTest < ActiveSupport::TestCase
  RESULT = { summary: "A promise to guard the eyes.", explanation: "x" * 220, context: "y" * 130,
             questions: [ "One?", "Two?", "Three?" ], model: "gemini-2.5-flash" }.freeze

  setup do
    ScriptureVerse.create!(translation: "kjv", book: 19, chapter: 101, verse: 3, text: "I will set no wicked thing before mine eyes.")
    @calls = 0
    @writer = ->(**) { @calls += 1; RESULT }
  end

  def with_real_provider(&block)
    Ai::Moderation::Client.stub(:stub?, false, &block)
  end

  test "writes and stores the insight once (idempotent)" do
    with_real_provider do
      Ai::Bible::ScriptureInsightWriter.stub(:call, @writer) do
        ScriptureInsightJob.perform_now("psalm-101-3")
        ScriptureInsightJob.perform_now("psalms-101-3")
      end
    end

    assert_equal 1, @calls
    insight = ScriptureInsight.find_by!(slug: "psalm-101-3")
    assert_equal "Psalm 101:3", insight.reference
    assert_equal "gemini-2.5-flash", insight.model
    assert_equal 3, insight.question_list.size
    assert insight.generated_at
  end

  test "stops at the hard cap" do
    stub_const_cap(0) do
      with_real_provider do
        Ai::Bible::ScriptureInsightWriter.stub(:call, @writer) { ScriptureInsightJob.perform_now("psalm-101-3") }
      end
    end
    assert_equal 0, @calls
    assert_not ScriptureInsight.exists?
  end

  test "never stores the offline stub's output" do
    Ai::Moderation::Client.stub(:stub?, true) do
      Ai::Bible::ScriptureInsightWriter.stub(:call, @writer) { ScriptureInsightJob.perform_now("psalm-101-3") }
    end
    assert_equal 0, @calls
  end

  test "an AI failure is counted, not raised" do
    recorded = []
    failing = ->(**) { raise Ai::Moderation::Client::ApiError, "gemini 503" }
    with_real_provider do
      Ai::Bible::ScriptureInsightWriter.stub(:call, failing) do
        FeatureFailure.stub(:record, ->(feature, reason) { recorded << [ feature, reason ] }) do
          assert_nothing_raised { ScriptureInsightJob.perform_now("psalm-101-3") }
        end
      end
    end
    assert_equal :scripture_insights, recorded.first&.first
    assert_not ScriptureInsight.exists?
  end

  test "the concurrency key accepts every argument" do
    assert_nothing_raised { ScriptureInsightJob.new("psalm-23").concurrency_key }
    assert_nothing_raised { ScriptureInsightJob.new("psalm-23", true).concurrency_key }
  end

  test "the writer parses and validates the model's JSON" do
    reply = { "model" => "gemini-2.5-flash", "content" => [ { "type" => "text", "text" => JSON.dump(
      summary: "About \"eyes\".", explanation: "e" * 220, context: "c" * 130, questions: [ "a?", "b?", "c?", "d?" ]) } ] }
    Ai::Moderation::Client.stub(:call, reply) do
      result = Ai::Bible::ScriptureInsightWriter.call(reference: Scripture::Reference.parse("Psalm 101:3"), passage_text: "text")
      assert_equal "About eyes.", result[:summary]
      assert_equal 3, result[:questions].size
    end

    short = { "content" => [ { "type" => "text", "text" => JSON.dump(summary: "s", explanation: "too short", context: "c", questions: []) } ] }
    Ai::Moderation::Client.stub(:call, short) do
      assert_raises(Ai::Bible::ScriptureInsightWriter::ParseError) do
        Ai::Bible::ScriptureInsightWriter.call(reference: Scripture::Reference.parse("Psalm 101:3"), passage_text: "text")
      end
    end
  end

  private

  def stub_const_cap(value)
    original = ScriptureInsight::CAP
    ScriptureInsight.send(:remove_const, :CAP)
    ScriptureInsight.const_set(:CAP, value)
    yield
  ensure
    ScriptureInsight.send(:remove_const, :CAP)
    ScriptureInsight.const_set(:CAP, original)
  end
end

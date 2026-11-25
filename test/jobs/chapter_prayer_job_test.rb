# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "rake"

# "Read your Bible, pray every day": one stored prayer per chapter, written in
# the background (never on a page view), checked by guardrails, with a plain
# fallback meanwhile. The AI is always stubbed here.
class ChapterPrayerJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  PRAYER = "Lord Jesus, thank you that you came to give light to everyone who believes in you, as John 3 says. " \
           "Like Nicodemus I come to you with questions at night, and I ask for a heart that is born again by your Spirit. " \
           "Help me to trust that you sent your Son not to condemn me but to save. Teach me to walk in the light today. Amen."
  RESULT = { prayer: PRAYER, verses: [ "John 3:16", "John 3:17" ], model: "gpt-4o-mini" }.freeze

  setup do
    ScriptureVerse.create!(translation: "kjv", book: 43, chapter: 3, verse: 16, text: "For God so loved the world.")
    @calls = 0
    @writer = ->(**) { @calls += 1; RESULT }
  end

  def with_real_provider(&block)
    Ai::Moderation::Client.stub(:stub?, false, &block)
  end

  def reply(prayer, verses)
    { "model" => "gpt-4o-mini", "content" => [ { "type" => "text", "text" => JSON.dump(prayer: prayer, verses: verses) } ] }
  end

  def write(prayer, verses = [ "John 3:16" ])
    Ai::Moderation::Client.stub(:call, reply(prayer, verses)) do
      Ai::Bible::ChapterPrayerWriter.call(reference: Scripture::Reference.parse("John 3"), passage_text: "text")
    end
  end

  test "writes and stores the prayer once per chapter" do
    with_real_provider do
      Ai::Bible::ChapterPrayerWriter.stub(:call, @writer) do
        ChapterPrayerJob.perform_now("john-3")
        ChapterPrayerJob.perform_now("john-3-16") # a verse slug means its chapter
      end
    end
    assert_equal 1, @calls
    prayer = ChapterPrayer.find_by!(slug: "john-3")
    assert_equal "John 3", prayer.reference
    assert_equal [ "John 3:16", "John 3:17" ], prayer.verse_list

    shown = ChapterPrayer.for(Scripture::Reference.parse("John 3"))
    assert shown.stored?
    assert_equal PRAYER, shown.body
    assert_equal %w[john-3-16 john-3-17], shown.verse_references.map(&:slug)
  end

  test "a chapter without a prayer gets the fallback at once and one background job" do
    chapter = Scripture::Reference.parse("John 3")
    with_real_provider do
      assert_enqueued_with(job: ChapterPrayerJob, args: [ "john-3" ]) do
        shown = ChapterPrayer.for(chapter)
        refute shown.stored?
        assert_includes shown.body, "Lord, thank you for speaking through John 3 today."
        assert shown.body.end_with?("Amen.")
      end
    end
  end

  test "never asks for (or stores) anything while the offline stub is active" do
    Ai::Moderation::Client.stub(:stub?, true) do
      assert_no_enqueued_jobs { ChapterPrayer.for(Scripture::Reference.parse("John 3")) }
      Ai::Bible::ChapterPrayerWriter.stub(:call, @writer) { ChapterPrayerJob.perform_now("john-3") }
    end
    assert_equal 0, @calls
    refute ChapterPrayer.exists?
  end

  test "an AI or guardrail failure is counted, not raised, and nothing is stored" do
    recorded = []
    failing = ->(**) { raise Ai::Bible::ChapterPrayerWriter::ParseError, "blocked phrasing" }
    with_real_provider do
      Ai::Bible::ChapterPrayerWriter.stub(:call, failing) do
        FeatureFailure.stub(:record, ->(feature, reason) { recorded << [ feature, reason ] }) do
          assert_nothing_raised { ChapterPrayerJob.perform_now("john-3") }
        end
      end
    end
    assert_equal :chapter_prayers, recorded.first&.first
    refute ChapterPrayer.exists?
  end

  test "the writer accepts a careful prayer and keeps only verses from this chapter" do
    result = write(PRAYER, [ "John 3:16", "Romans 8:1", "John 3:17", "John 4:1" ])
    assert_equal PRAYER, result[:prayer]
    assert_equal [ "John 3:16", "John 3:17" ], result[:verses]
  end

  test "the writer rejects prayers that break the guardrails" do
    bad = {
      "speaks for God" => "Lord, I hear you. God says to me today that every door will open. I am grateful for John 3. I trust you with my nights. Help me believe. Amen.",
      "prosperity" => "Lord, as I read John 3 I ask you to bless me with wealth and open a financial blessing for my family this week. I receive new birth. I trust you. Amen.",
      "too short" => "Lord, thank you for John 3. Amen.",
      "not first person" => "Lord Jesus, you came to give light to all who believe, as John 3 says so clearly to every reader. You sent your Son not to condemn but to save the world. You teach us to walk in the light. Amen.",
      "old English" => "Lord, I thank thee for John 3 and for thy Son whom thou hast sent into the world for me. Help me to walk in the light all of this day. Keep me close to you tonight. Amen."
    }
    bad.each do |why, text|
      assert_raises(Ai::Bible::ChapterPrayerWriter::ParseError, why) { write(text) }
    end
    assert_raises(Ai::Bible::ChapterPrayerWriter::ParseError, "needs a verse from the chapter") { write(PRAYER, [ "Romans 8:1" ]) }
    assert_raises(Ai::Bible::ChapterPrayerWriter::ParseError, "not JSON") do
      Ai::Moderation::Client.stub(:call, { "content" => [ { "type" => "text", "text" => "Dear Lord…" } ] }) do
        Ai::Bible::ChapterPrayerWriter.call(reference: Scripture::Reference.parse("John 3"), passage_text: "text")
      end
    end
  end

  test "the concurrency key accepts every argument" do
    assert_nothing_raised { ChapterPrayerJob.new("john-3").concurrency_key }
    assert_nothing_raised { ChapterPrayerJob.new("john-3", true).concurrency_key }
  end

  test "the rake task enqueues the next chapters in reading-plan order" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("bible_today:prayers")
    ChapterPrayer.create!(slug: "john-1", reference: "John 1", body: PRAYER, verses: [ "John 1:1" ], generated_at: Time.current)
    with_real_provider do
      assert_enqueued_jobs 3, only: ChapterPrayerJob do
        assert_output(/Enqueued 3 chapter prayers/) { Rake::Task["bible_today:prayers"].execute(Rake::TaskArguments.new([ :count ], [ "3" ])) }
      end
    end
    assert_equal %w[john-2 john-3 john-4], enqueued_jobs.select { |j| j["job_class"] == "ChapterPrayerJob" }.map { |j| j["arguments"].first }
  end
end

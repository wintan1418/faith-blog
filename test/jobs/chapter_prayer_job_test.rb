# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "rake"

# "Read your Bible, pray every day": one stored prayer burden per chapter
# (today's burden, prayer points tied to verses, a closing prayer), written
# in the background (never on a page view) from the chapter's own text,
# checked by guardrails and retried when it breaks one, with a fallback
# meanwhile. Older, shallow prayers are rewritten. The AI is always stubbed.
class ChapterPrayerJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  BURDEN = "John 3 calls us to pray for new birth by the Spirit, and to trust the Son whom God gave so that the world might be saved, not condemned."
  POINTS = [
    { "kind" => "praise", "text" => "Praise God for loving the world so much that he gave his only Son.", "reference" => "John 3:16" },
    { "kind" => "confession", "text" => "Confess the times you have loved darkness and hidden from the light.", "reference" => "John 3:19" },
    { "kind" => "intercession", "text" => "Pray for friends who, like Nicodemus, have honest questions about Jesus.", "reference" => "John 3:2" },
    { "kind" => "application", "text" => "Ask the Spirit to make you new, and walk today as someone born from above.", "reference" => "John 3:5-6" }
  ].freeze
  PRAYER = "Father, you loved the world so much that you gave your only Son, and I stand amazed. " \
           "Like Nicodemus I come to you with questions, and I ask you to make me new by your Spirit. " \
           "I confess that I have sometimes loved the dark and hidden from your light. " \
           "Give my friends who are searching the same honest courage to come to Jesus. " \
           "Help me to live in the light today, trusting that your Son came to save and not to condemn. Amen."
  PAYLOAD = { "themes" => [ "New birth by the Spirit", "God's love in giving the Son", "Light and darkness" ],
              "key_verses" => [ "John 3:16", "John 3:3" ], "burden" => BURDEN, "points" => POINTS, "prayer" => PRAYER }.freeze
  TEXTS = { "kjv" => (1..21).map { |v| [ v, "John three verse #{v}." ] }, "web" => (1..21).map { |v| [ v, "Web verse #{v}." ] } }.freeze

  setup do
    ScriptureVerse.insert_all((1..21).flat_map { |v| [ { translation: "kjv", book: 43, chapter: 3, verse: v, text: "John three verse #{v}." },
                                                       { translation: "web", book: 43, chapter: 3, verse: v, text: "Web verse #{v}." } ] })
    @calls = 0
    @writer = ->(**) { @calls += 1; writer_result }
  end

  def writer_result
    { themes: PAYLOAD["themes"], key_verses: [ "John 3:16", "John 3:3" ], burden: BURDEN, prayer: PRAYER, model: "gpt-4o-mini",
      points: POINTS.map { |p| { text: p["text"], reference: Scripture::Reference.parse(p["reference"]).to_s, kind: p["kind"] } } }
  end

  def with_real_provider(&block)
    Ai::Moderation::Client.stub(:stub?, false, &block)
  end

  def reply(payload)
    { "model" => "gpt-4o-mini", "content" => [ { "type" => "text", "text" => JSON.dump(payload) } ] }
  end

  # Runs the writer against a queue of replies; returns [result or error, prompts sent].
  def write(*payloads)
    prompts = []
    queue = payloads.dup
    fake = lambda do |system:, user:, **|
      prompts << [ system, user ]
      reply(queue.length > 1 ? queue.shift : queue.first)
    end
    result = Ai::Moderation::Client.stub(:call, fake) do
      Ai::Bible::ChapterPrayerWriter.call(reference: Scripture::Reference.parse("John 3"), texts: TEXTS)
    rescue Ai::Bible::ChapterPrayerWriter::ParseError => e
      e
    end
    [ result, prompts ]
  end

  test "writes and stores the prayer burden once per chapter" do
    with_real_provider do
      Ai::Bible::ChapterPrayerWriter.stub(:call, @writer) do
        ChapterPrayerJob.perform_now("john-3")
        ChapterPrayerJob.perform_now("john-3-16") # a verse slug means its chapter
      end
    end
    assert_equal 1, @calls
    prayer = ChapterPrayer.find_by!(slug: "john-3")
    assert_equal ChapterPrayer::VERSION, prayer.version
    assert_equal BURDEN, prayer.burden
    assert_equal [ "John 3:16", "John 3:3" ], prayer.key_verses

    shown = ChapterPrayer.for(Scripture::Reference.parse("John 3"))
    assert shown.stored?
    assert shown.current?
    assert_equal BURDEN, shown.burden
    assert_equal PRAYER, shown.body
    assert_equal 4, shown.points.size
    assert_equal [ "Praise", "Confess", "Intercede", "Obey" ], shown.points.map(&:label)
    assert_equal "v5", shown.points.last.anchor
    assert_equal %w[john-3-16 john-3-3], shown.verse_references.map(&:slug)
  end

  test "the writer is given the whole chapter, KJV and WEB, verse by verse" do
    result, prompts = write(PAYLOAD)
    refute_kind_of Exception, result
    system, user = prompts.first
    assert_includes system, "Today's burden"
    assert_includes system, "points"
    assert_includes user, "Chapter: John 3 (21 verses)"
    assert_includes user, "King James Version:\n1 John three verse 1.\n2 John three verse 2."
    assert_includes user, "World English Bible:\n1 Web verse 1."
    assert_includes user, "21 Web verse 21."
    assert_equal BURDEN, result[:burden]
    assert_equal [ "John 3:16", "John 3:19", "John 3:2", "John 3:5–6" ], result[:points].map { |p| p[:reference] }
  end

  test "a chapter without a prayer gets the fallback at once and one background job" do
    chapter = Scripture::Reference.parse("John 3")
    with_real_provider do
      assert_enqueued_with(job: ChapterPrayerJob, args: [ "john-3" ]) do
        shown = ChapterPrayer.for(chapter)
        refute shown.stored?
        assert_empty shown.points
        assert_includes shown.burden, "John 3"
        assert shown.body.end_with?("Amen.")
        assert_no_match(/thank you for/i, shown.body)
      end
    end
  end

  test "an older (version 1) prayer is still shown while a deeper one is written, then replaced" do
    old = ChapterPrayer.create!(slug: "john-3", reference: "John 3", version: 1, verses: [ "John 3:16" ], generated_at: 1.day.ago,
                                body: "Lord, thank you for John 3. Amen.")
    chapter = Scripture::Reference.parse("John 3")
    with_real_provider do
      assert_enqueued_with(job: ChapterPrayerJob, args: [ "john-3" ]) do
        shown = ChapterPrayer.for(chapter)
        assert shown.stored?
        refute shown.current?
        assert_equal "Lord, thank you for John 3. Amen.", shown.body
        assert_empty shown.points
      end
      Ai::Bible::ChapterPrayerWriter.stub(:call, @writer) { ChapterPrayerJob.perform_now("john-3") }
    end
    assert_equal 1, @calls
    assert_equal ChapterPrayer::VERSION, old.reload.version
    assert_equal PRAYER, old.body
    assert_equal 1, ChapterPrayer.count
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

  test "every prayer point must cite a verse that exists in this chapter; a bad reply is retried with the reason" do
    wrong_chapter = PAYLOAD.merge("points" => POINTS.each_with_index.map { |p, i| i.zero? ? p.merge("reference" => "Romans 8:1") : p })
    result, prompts = write(wrong_chapter, PAYLOAD)
    refute_kind_of Exception, result
    assert_equal 2, prompts.size
    assert_match(/rejected: prayer point reference "Romans 8:1" is not a verse of John 3/, prompts.last.last)

    no_such_verse = PAYLOAD.merge("points" => POINTS.map { |p| p.merge("reference" => "John 3:40") })
    result, prompts = write(no_such_verse)
    assert_kind_of Ai::Bible::ChapterPrayerWriter::ParseError, result
    assert_equal Ai::Bible::ChapterPrayerWriter::MAX_ATTEMPTS, prompts.size

    beyond_the_text = PAYLOAD.merge("key_verses" => [ "John 3:36" ]) # in the KJV, but not in the text we sent
    assert_kind_of Ai::Bible::ChapterPrayerWriter::ParseError, write(beyond_the_text).first
  end

  test "the writer strips a repeated reference from a point's words" do
    with_ref = PAYLOAD.merge("points" => POINTS.map { |p| p.merge("text" => "#{p['text'].delete_suffix('.')} (#{p['reference']})") })
    result, = write(with_ref)
    assert_equal "Praise God for loving the world so much that he gave his only Son.", result[:points].first[:text]
  end

  test "the writer rejects shallow, unsafe or malformed burdens" do
    bad = {
      "generic filler" => PAYLOAD.merge("prayer" => PRAYER.sub("and I stand amazed.", "and thank you for this chapter.")),
      "thanks for the chapter by name" => PAYLOAD.merge("burden" => "Thank you for John 3 and everything in it, Lord, and help us to pray through it well today."),
      "speaks for God" => PAYLOAD.merge("burden" => "God says to you today that every door will open, so pray boldly and expect it all to come to pass now."),
      "prosperity" => PAYLOAD.merge("points" => POINTS + [ { "kind" => "application", "text" => "Ask God to bless you with wealth and a financial breakthrough this week.", "reference" => "John 3:16" } ]),
      "old English" => PAYLOAD.merge("prayer" => PRAYER.sub("I stand amazed", "I thank thee")),
      "too few points" => PAYLOAD.merge("points" => POINTS.first(2)),
      "one kind only" => PAYLOAD.merge("points" => POINTS.map { |p| p.merge("kind" => "praise") }),
      "unknown kind" => PAYLOAD.merge("points" => POINTS.map { |p| p.merge("kind" => "declaration") }),
      "short closing prayer" => PAYLOAD.merge("prayer" => "Lord, I love you. Amen."),
      "not first person" => PAYLOAD.merge("prayer" => PRAYER.gsub(/\b(I|me|my)\b/, "we").gsub("I ", "we ")),
      "no themes" => PAYLOAD.merge("themes" => [])
    }
    bad.each do |why, payload|
      error = write(payload).first
      assert_kind_of Ai::Bible::ChapterPrayerWriter::ParseError, error, why
      puts "#{why}: #{error.message}" if ENV["SHOW_REASONS"]
    end
    _, prompts = write("not json")
    assert_equal Ai::Bible::ChapterPrayerWriter::MAX_ATTEMPTS, prompts.size
  end

  test "the concurrency key accepts every argument" do
    assert_nothing_raised { ChapterPrayerJob.new("john-3").concurrency_key }
    assert_nothing_raised { ChapterPrayerJob.new("john-3", true).concurrency_key }
  end

  test "the rake task enqueues the next chapters missing or outdated, in reading-plan order" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("bible_today:prayers")
    ChapterPrayer.create!(slug: "john-1", reference: "John 1", body: PRAYER, burden: BURDEN, version: ChapterPrayer::VERSION,
                          verses: [ "John 1:1" ], generated_at: Time.current)
    ChapterPrayer.create!(slug: "john-2", reference: "John 2", body: PRAYER, version: 1, verses: [ "John 2:1" ], generated_at: Time.current)
    with_real_provider do
      assert_enqueued_jobs 3, only: ChapterPrayerJob do
        assert_output(/Enqueued 3 chapter prayers/) { Rake::Task["bible_today:prayers"].execute(Rake::TaskArguments.new([ :count ], [ "3" ])) }
      end
    end
    assert_equal %w[john-2 john-3 john-4], enqueued_jobs.select { |j| j["job_class"] == "ChapterPrayerJob" }.map { |j| j["arguments"].first }
    assert_output(/1 current, 1 outdated/) { Rake::Task["bible_today:prayers_status"].execute }
  end
end

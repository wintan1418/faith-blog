# frozen_string_literal: true

require "test_helper"

class BibleQuiz::AuditTest < ActiveSupport::TestCase
  include BibleTextFixture

  setup do
    seed_bible_text
    @user = User.create!(username: "audit_p", email: "audit_p@example.com", password: SecureRandom.base58(16))
  end

  # Rows as they are in production: saved before the giveaway rule existed.
  def legacy(**attrs)
    q = BibleQuizQuestion.new({ difficulty: "easy", theme: "faith", explanation: "x" }.merge(attrs))
    q.fingerprint = SecureRandom.hex(20)
    q.save!(validate: false)
    q.update_columns(verse_key: nil, content_key: nil)
    q
  end

  def phil(prompt, **attrs)
    legacy(kind: "reference", prompt: prompt, reference: "Philippians 4:13", correct_index: 0,
           choices: [ "Philippians 4:13", "Romans 8:28", "John 3:16", "Isaiah 40:31" ], **attrs)
  end

  def run_audit(apply:, ids: [])
    BibleQuiz::Audit.new(apply: apply, retire_ids: ids, out: StringIO.new).call
  end

  test "retires giveaways, biblical decoys and duplicates; keeps the most played of each group" do
    giveaway = legacy(kind: "reference", prompt: "Ephesians 2:8-9 emphasizes grace. What is the chapter:verse?",
                      reference: "Ephesians 2:8-9", correct_index: 0,
                      choices: [ "Ephesians 2:8-9", "Romans 3:23", "John 3:16", "Titus 3:5" ])
    bad_phrase = legacy(kind: "true_phrase", prompt: "Which of these is in the Bible?", reference: "1 Thessalonians 5:17",
                        correct_index: 0, choices: [ "Pray without ceasing.", "Faith without works is dead.",
                                                     "Bear ye one another's burdens.", "Love covers a multitude of sins." ])
    good_phrase = legacy(kind: "true_phrase", prompt: "Which does Scripture say?", reference: "1 Thessalonians 5:17",
                         correct_index: 2, choices: [ "God helps those who help themselves", "This too shall pass",
                                                      "Pray without ceasing.", "Cleanliness is next to godliness" ])
    old = phil("Where is 'I can do all things through Christ'?")
    played = phil("Which verse says 'I can do all things'?")
    flagged = phil("Locate 'through Christ which strengtheneth me'.", flags_count: 1)
    BibleQuizQuestion.mark_seen!(user: @user, question_ids: [ played.id ])
    pending = Report.create!(reporter: @user, reportable: old, reason: "Quiz question: Unclear question.")

    dry = run_audit(apply: false)
    assert_equal [ 1, 1, 2, 1 ], [ dry.giveaways, dry.phrases_wrong, dry.duplicates, dry.duplicate_groups ]
    assert_equal 6, BibleQuizQuestion.trusted.count, "dry run changes nothing"
    assert_nil old.reload.content_key

    s = run_audit(apply: true)
    assert_equal 4, s.retired
    assert giveaway.reload.retired?
    assert bad_phrase.reload.retired?
    assert_not good_phrase.reload.retired?
    assert_not played.reload.retired?, "most played copy is kept"
    assert old.reload.retired?
    assert flagged.reload.retired?
    assert pending.reload.resolved?
    assert_equal "reference|philippians 4:13", played.content_key

    again = run_audit(apply: true)
    assert_equal 0, again.retired, "idempotent"
    assert_equal 0, again.keys_backfilled
  end

  test "retires listed ids, and a listed row is never the one kept" do
    a = phil("Where is 'I can do all things'?")
    b = phil("Which verse says 'I can do all things'?")
    c = legacy(kind: "what_does", prompt: "What does grace mean?", reference: "Ephesians 2:8", correct_index: 0,
               choices: [ "Unmerited favor", "Works", "Law", "Wages" ])

    s = run_audit(apply: true, ids: [ a.id, c.id ])
    assert_equal 2, s.explicit
    assert_equal 0, s.duplicates
    assert a.reload.retired?
    assert c.reload.retired?
    assert_not b.reload.retired?
  end

  test "without the Bible text, true_phrase questions are left alone" do
    ScriptureVerse.delete_all
    q = legacy(kind: "true_phrase", prompt: "Which is in the Bible?", reference: "", correct_index: 0,
               choices: [ "Pray without ceasing.", "Faith without works is dead.", "Jesus wept.", "God is love." ])
    s = run_audit(apply: true)
    assert_equal 1, s.phrases_unchecked
    assert_not q.reload.retired?
  end
end

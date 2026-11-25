# frozen_string_literal: true

require "test_helper"

class BibleQuizQuestionTest < ActiveSupport::TestCase
  def build(**attrs)
    BibleQuizQuestion.new({ kind: "what_does", prompt: "What does 'justified by faith' mean?",
                            choices: [ "Saved by works", "Declared righteous", "Condemned", "Forgotten" ],
                            correct_index: 1, difficulty: "easy" }.merge(attrs))
  end

  test "a clean question is valid" do
    assert build.valid?
  end

  test "rejects lettered options typed into the question" do
    question = build(prompt: "What does it mean? A) Saved by works B) Declared righteous")
    assert_not question.valid?
    assert question.errors[:prompt].any?
  end

  test "rejects bare letters as choices" do
    assert_not build(choices: %w[C D B A]).valid?
  end

  test "reference questions need full references" do
    assert_not build(kind: "reference", choices: [ "1:2", "John 3:16", "Romans 3:23", "Acts 2:38" ]).valid?
    assert build(kind: "reference", choices: [ "1 John 2:25", "John 3:16", "Romans 3:23", "Acts 2:38" ]).valid?
  end

  # Trello #102: a theme's round never borrows from other themes.
  test "serve_round keeps to the theme, widening only the difficulty" do
    user = User.create!(username: "bqq_player", email: "bqq_player@example.com", password: SecureRandom.base58(16))
    cross = Array.new(2) { |i| build(prompt: "Cross #{i}?", theme: "the_cross", difficulty: "hard").tap(&:save!) }
    Array.new(8) { |i| build(prompt: "Faith #{i}?", theme: "faith").tap(&:save!) }

    rows = BibleQuizQuestion.serve_round(user: user, theme: "the_cross", difficulty: "easy", count: 5)
    assert_equal cross.map(&:id).sort, rows.map(&:id).sort

    assert_equal 5, BibleQuizQuestion.serve_round(user: user, count: 5).size, "no theme: anything goes"
  end

  def player(name = "bqq_p#{SecureRandom.hex(3)}")
    User.create!(username: name, email: "#{name}@example.com", password: SecureRandom.base58(16))
  end

  def ref_q(prompt:, reference: "Philippians 4:13", answer: "Philippians 4:13", **attrs)
    build(kind: "reference", prompt: prompt, reference: reference,
          choices: [ answer, "Romans 8:28", "John 3:16", "Isaiah 40:31" ], correct_index: 0, **attrs)
  end

  # Report #937: "Ephesians 2:8-9 emphasizes grace … What is the chapter:verse?"
  test "reference: a prompt that cites the verse or holds the answer is rejected" do
    q = ref_q(prompt: "Ephesians 2:8-9 emphasizes grace and forgiveness. What is the chapter:verse?",
              reference: "Ephesians 2:8-9", answer: "Ephesians 2:8-9")
    assert_not q.valid?
    assert_match(/gives the answer away/, q.errors[:prompt].join)

    assert_not ref_q(prompt: "Where is 'I can do all things through Christ' (Phil 4:13)?").valid?, "abbreviated citation"
    assert_not ref_q(prompt: "Philippians 4:13: 'I can do all things.' Where is it?", answer: "Romans 8:28").valid?,
               "the question's own verse, even followed by a colon"
    assert_not ref_q(prompt: "Which reference is 4:13 — 'I can do all things through Christ'?").valid?, "chapter:verse alone"
    assert ref_q(prompt: "'I can do all things through Christ which strengtheneth me.' Where is this written?").valid?
    assert ref_q(prompt: "'For God so loved the world' is quoted in 1 John 4:9's spirit. Where is 'I can do all things'?").valid?,
           "a different verse in the prompt is fine"
  end

  test "fill_blank: the blanked word may not appear elsewhere in the prompt" do
    base = { kind: "fill_blank", reference: "Ephesians 2:8", choices: %w[faith works grace law], correct_index: 0 }
    assert_not build(**base, prompt: "By grace are ye saved through ____; faith is the gift of God.").valid?
    assert build(**base, prompt: "For by grace are ye saved through ____; and that not of yourselves.").valid?
  end

  test "which_book: the prompt may not name the answer's book" do
    base = { kind: "which_book", reference: "Romans 8:28", choices: [ "Romans", "Galatians", "Hebrews", "James" ], correct_index: 0 }
    assert_not build(**base, prompt: "In Romans, Paul writes 'all things work together for good'. Which book?").valid?
    assert_not build(**base, prompt: "'All things work together for good' (Romans 8:28) — which book?").valid?
    assert build(**base, prompt: "Which book says 'all things work together for good to them that love God'?").valid?

    john = { kind: "which_book", reference: "John 11:35", choices: [ "John", "Mark", "Luke", "Acts" ], correct_index: 0 }
    assert build(**john, prompt: "Which book records that Jesus wept, after John the Baptist had died?").valid?,
           "a person's name is not the book"
    assert_not build(**john, prompt: "Which book is 'Jesus wept' (John 11:35) from?").valid?
  end

  test "content keys: the same question in other words shares a key" do
    a = ref_q(prompt: "Where is 'I can do all things through Christ'?").tap(&:save!)
    b = ref_q(prompt: "Which verse says: I can do all things through Christ who strengthens me?", reference: "Phil. 4:13")
    b.valid?
    assert_equal "philippians 4:13", a.verse_key
    assert_equal "reference|philippians 4:13", a.content_key
    assert_equal a.content_key, b.content_key

    blank = build(kind: "fill_blank", prompt: "I can do all things through ____.", reference: "Philippians 4:13",
                  choices: %w[Christ faith prayer love], correct_index: 0)
    blank.valid?
    assert_equal "fill_blank|philippians 4:13|christ", blank.content_key
    assert_equal "philippians 4:13", blank.verse_key
  end

  # Report #704: "This question was repeated twice in a row".
  test "import skips a question the pool already has in other words" do
    q = Struct.new(:kind, :prompt, :choices, :correct_index, :reference, :explanation, :theme, :difficulty, keyword_init: true)
    make = ->(prompt) { q.new(kind: "reference", prompt: prompt, reference: "Philippians 4:13", explanation: "x", theme: "faith",
                              difficulty: "easy", correct_index: 0,
                              choices: [ "Philippians 4:13", "Romans 8:28", "John 3:16", "Isaiah 40:31" ]) }
    assert_equal 1, BibleQuizQuestion.import_from_generator!([ make.("Where is 'I can do all things'?"),
                                                               make.("Find the verse: 'I can do all things through Christ'.") ])
    assert_equal 0, BibleQuizQuestion.import_from_generator!([ make.("Which verse: 'through Christ which strengtheneth me'?") ])

    BibleQuizQuestion.last.retire!
    assert_equal 1, BibleQuizQuestion.import_from_generator!([ make.("Locate: 'I can do all things'.") ]),
                 "a retired copy doesn't block a new one"
  end

  test "a round never holds two questions on the same verse" do
    user = player
    6.times { |i| ref_q(prompt: "Take #{i}: 'I can do all things'?").save! }
    ref_q(prompt: "'For God so loved the world' — where?", reference: "John 3:16",
          answer: "John 3:16").tap { |r| r.choices = [ "John 3:16", "Romans 8:28", "Philippians 4:13", "Isaiah 40:31" ] }.save!

    10.times do
      rows = BibleQuizQuestion.serve_round(user: user, count: 5)
      assert_equal rows.map(&:verse_key).uniq.size, rows.size
      assert_equal 2, rows.size
    end
  end

  test "sample_for prefers verses the user hasn't seen, counting any question on a verse as seeing it" do
    user = player
    phil = Array.new(3) { |i| ref_q(prompt: "Take #{i}: 'I can do all things through Christ'?").tap(&:save!) }
    john = ref_q(prompt: "'For God so loved the world' — where?", reference: "John 3:16", answer: "John 3:16")
    john.choices = [ "John 3:16", "Romans 8:28", "Philippians 4:13", "Isaiah 40:31" ]
    john.save!

    BibleQuizQuestion.mark_seen!(user: user, question_ids: [ phil.first.id ])
    rows = BibleQuizQuestion.sample_for(user: user, count: 1)
    assert_equal [ john.id ], rows.map(&:id), "an unseen row of a seen verse waits behind a fresh verse"

    BibleQuizQuestion.mark_seen!(user: user, question_ids: [ john.id ])
    rows = BibleQuizQuestion.sample_for(user: user, count: 2)
    assert_equal 2, rows.size
    assert_equal rows.map(&:verse_key).uniq.size, 2
    assert_not_includes rows.map(&:id), phil.first.id, "unseen rows come before seen ones"
  end
end

# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Trello #102: questions written for a theme must be about that theme.
class Ai::Bible::QuizThemeTest < ActiveSupport::TestCase
  def ai_reply(payload)
    { "content" => [ { "type" => "text", "text" => payload.to_json } ] }
  end

  def question(prompt, link: "It is about the cross")
    { "kind" => "what_does", "prompt" => prompt, "choices" => %w[A1 B1 C1 D1], "correct_index" => 0,
      "reference" => "Galatians 6:14", "explanation" => "KJV", "theme_link" => link }
  end

  test "every theme has books that speak to it, and the book hint comes from them" do
    assert_equal Ai::Bible::QuizGenerator::THEMES.keys.sort, Ai::Bible::QuizGenerator::THEME_BOOKS.keys.sort

    prompts = []
    fake = lambda do |system:, user:, images: []|
      prompts << user
      ai_reply("questions" => [ question("Why did Paul glory only in the cross?") ])
    end
    Ai::Moderation::Client.stub(:call, fake) do
      20.times { Ai::Bible::QuizGenerator.call(theme: "the_cross", difficulty: "easy") }
    end

    books = prompts.map { |p| p[/SUGGESTED BOOK \(only where it speaks to the theme\): (.+)$/, 1] }
    assert_empty books - Ai::Bible::QuizGenerator::THEME_BOOKS["the_cross"]
    assert(prompts.all? { |p| p.include?("THEME: the_cross — the cross") })
    assert(prompts.all? { |p| p.include?("clearly about the cross — atonement") })
  end

  test "the system prompt asks for on-theme questions with a stated link" do
    prompt = Ai::Bible::QuizGenerator::SYSTEM_PROMPT
    assert_includes prompt, "must be ABOUT the assigned THEME"
    assert_includes prompt, '"theme_link": string'
  end

  test "questions with no link to the theme are dropped, and tagged with the asked theme" do
    reply = ai_reply("questions" => [
      question("What did Christ blot out, nailing it to his cross?"),
      question("Who greeted Gaius in 3 John?", link: ""),
      question("Which epistle mentions Onesimus?", link: nil)
    ])
    questions = Ai::Moderation::Client.stub(:call, reply) do
      Ai::Bible::QuizGenerator.call(theme: "the_cross", difficulty: "medium")
    end

    assert_equal [ "What did Christ blot out, nailing it to his cross?" ], questions.map(&:prompt)
    assert_equal [ "the_cross" ], questions.map(&:theme)
  end

  test "a batch with nothing on theme is an error, not a silent mix" do
    reply = ai_reply("questions" => [ question("Who greeted Gaius?", link: "") ])
    Ai::Moderation::Client.stub(:call, reply) do
      assert_raises(Ai::Bible::QuizGenerator::ParseError) { Ai::Bible::QuizGenerator.call(theme: "the_cross") }
    end
  end

  test "the theme check returns only off-theme ids it was asked about" do
    on = BibleQuizQuestion.create!(kind: "what_does", prompt: "What did the blood of his cross make?",
                                   choices: %w[Peace War Bread Wine], correct_index: 0, theme: "the_cross")
    off = BibleQuizQuestion.create!(kind: "which_book", prompt: "Which book mentions Diotrephes?",
                                    choices: [ "3 John", "Jude", "Titus", "Acts" ], correct_index: 0, theme: "the_cross")
    seen = nil
    fake = lambda do |system:, user:, images: []|
      seen = user
      ai_reply("off_theme_ids" => [ off.id, 999_999 ])
    end
    ids = Ai::Moderation::Client.stub(:call, fake) { Ai::Bible::QuizThemeCheck.call(theme: "the_cross", questions: [ on, off ]) }

    assert_equal [ off.id ], ids
    assert_includes seen, "THEME: the_cross"
    assert_includes seen, "Diotrephes"
    assert_equal [], Ai::Bible::QuizThemeCheck.call(theme: "not_a_theme", questions: [ on ])
  end
end

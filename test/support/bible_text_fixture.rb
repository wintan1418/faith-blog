# frozen_string_literal: true

# A few verses of KJV / WEB / BSB text for tests that check quiz phrases
# against the Bible (BibleQuiz::PhraseCheck). Include and call seed_bible_text.
module BibleTextFixture
  VERSES = [
    # [book position, chapter, verse, kjv, web, bsb]
    [ 52, 5, 17, "Pray without ceasing.", "Pray without ceasing.", "Pray without ceasing." ],
    [ 59, 2, 20, "But wilt thou know, O vain man, that faith without works is dead?",
      "But do you want to know, vain man, that faith apart from works is dead?",
      "O foolish man, do you want evidence that faith without deeds is worthless?" ],
    [ 48, 6, 2, "Bear ye one another's burdens, and so fulfil the law of Christ.",
      "Bear one another's burdens, and so fulfill the law of Christ.",
      "Carry one another's burdens, and in this way you will fulfill the law of Christ." ],
    [ 60, 4, 8, "And above all things have fervent charity among yourselves: for charity shall cover the multitude of sins.",
      "And above all things be earnest in your love among yourselves, for love covers a multitude of sins.",
      "Above all, love one another deeply, because love covers over a multitude of sins." ],
    [ 50, 4, 13, "I can do all things through Christ which strengtheneth me.",
      "I can do all things through Christ, who strengthens me.",
      "I can do all things through Christ who gives me strength." ],
    [ 54, 6, 10, "For the love of money is the root of all evil: which while some coveted after, they have erred from the faith.",
      "For the love of money is a root of all kinds of evil.",
      "For the love of money is the root of all kinds of evil." ]
  ].freeze

  def seed_bible_text
    rows = VERSES.flat_map do |book, ch, v, kjv, web, bsb|
      { "kjv" => kjv, "web" => web, "bsb" => bsb }.map { |t, text| { translation: t, book: book, chapter: ch, verse: v, text: text } }
    end
    ScriptureVerse.insert_all!(rows)
  end
end

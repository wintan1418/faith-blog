# frozen_string_literal: true

# Semantic dedupe for the Bible Quiz: the SHA1 fingerprint of the exact prompt
# let rephrasings of the same question through (Philippians 4:13 was in the
# pool six times). verse_key is the verse a question is about ("philippians
# 4:13"); content_key is the question itself (kind + verse, plus the blanked
# word or the true phrase). Also indexes every translation's verse text for
# the true_phrase check (BibleQuiz::PhraseCheck) — the old index was KJV only.
class AddContentKeysToBibleQuizQuestions < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :bible_quiz_questions, :verse_key, :string, limit: 80 unless column_exists?(:bible_quiz_questions, :verse_key)
    add_column :bible_quiz_questions, :content_key, :string, limit: 255 unless column_exists?(:bible_quiz_questions, :content_key)
    add_index :bible_quiz_questions, :verse_key, algorithm: :concurrently, if_not_exists: true
    add_index :bible_quiz_questions, :content_key, algorithm: :concurrently, if_not_exists: true
    add_index :scripture_verses, "to_tsvector('english'::regconfig, text)", using: :gin,
              name: "index_scripture_verses_text_search", algorithm: :concurrently, if_not_exists: true

    BibleQuizQuestion.reset_column_information
    BibleQuizQuestion.find_each do |q|
      q.update_columns(verse_key: q.compute_verse_key, content_key: q.compute_content_key)
    end
  end

  def down
    remove_index :scripture_verses, name: "index_scripture_verses_text_search", if_exists: true
    remove_column :bible_quiz_questions, :content_key
    remove_column :bible_quiz_questions, :verse_key
  end
end

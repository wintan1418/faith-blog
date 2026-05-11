class CreateBibleQuizQuestions < ActiveRecord::Migration[8.0]
  def change
    create_table :bible_quiz_questions do |t|
      t.string  :kind,          null: false, limit: 32
      t.text    :prompt,        null: false
      t.jsonb   :choices,       null: false, default: []
      t.integer :correct_index, null: false
      t.string  :reference,     limit: 80
      t.text    :explanation
      t.string  :difficulty,    limit: 16, default: "medium"
      t.string  :fingerprint,   null: false   # for dedupe
      t.timestamps
    end
    add_index :bible_quiz_questions, :kind
    add_index :bible_quiz_questions, :fingerprint, unique: true
  end
end

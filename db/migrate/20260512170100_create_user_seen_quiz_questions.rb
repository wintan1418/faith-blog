class CreateUserSeenQuizQuestions < ActiveRecord::Migration[8.0]
  def change
    create_table :user_seen_quiz_questions do |t|
      t.references :user,                  null: false, foreign_key: true
      t.references :bible_quiz_question,   null: false, foreign_key: true, index: { name: "idx_seen_quiz_q" }
      t.datetime   :last_seen_at,          null: false
      t.timestamps
    end
    add_index :user_seen_quiz_questions, [ :user_id, :bible_quiz_question_id ],
              unique: true,
              name: "idx_seen_user_q"
    add_index :user_seen_quiz_questions, [ :user_id, :last_seen_at ],
              name: "idx_seen_user_recent"
  end
end

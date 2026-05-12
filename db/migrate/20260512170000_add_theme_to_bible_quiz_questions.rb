class AddThemeToBibleQuizQuestions < ActiveRecord::Migration[8.0]
  def change
    add_column :bible_quiz_questions, :theme, :string, limit: 32
    add_index  :bible_quiz_questions, :theme
    add_index  :bible_quiz_questions, [ :theme, :difficulty ]
  end
end

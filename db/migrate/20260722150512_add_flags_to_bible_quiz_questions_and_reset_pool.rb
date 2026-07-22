# frozen_string_literal: true

# Players can now flag a question whose answer is wrong; twice-flagged
# questions stop being served. Also purges the existing question pool:
# it accumulated AI questions generated before the accuracy hardening
# (players reported factually wrong answers), and the pool refills
# itself on demand from the stricter generator.
class AddFlagsToBibleQuizQuestionsAndResetPool < ActiveRecord::Migration[8.0]
  def up
    add_column :bible_quiz_questions, :flags_count, :integer, default: 0, null: false

    execute "DELETE FROM user_seen_quiz_questions"
    execute "DELETE FROM bible_quiz_questions"
  end

  def down
    remove_column :bible_quiz_questions, :flags_count
  end
end

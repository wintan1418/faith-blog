class CreateGameAttempts < ActiveRecord::Migration[8.0]
  def change
    create_table :game_attempts do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :kind,      null: false, default: 0
      t.integer :score,     null: false, default: 0
      t.integer :max_score, null: false, default: 0
      t.integer :duration_ms
      t.jsonb   :details, null: false, default: {}
      t.datetime :played_at, null: false
      t.timestamps
    end
    add_index :game_attempts, [ :user_id, :kind ]
    add_index :game_attempts, :played_at
    add_index :game_attempts, :kind
  end
end

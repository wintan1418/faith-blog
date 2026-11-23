# frozen_string_literal: true

# Seeds: engagement points. The ledger is the source of truth; users.seeds_total
# is a cached sum of it. One row per (user, kind, source) so an action never
# pays twice.
class CreateSeedEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :seed_events do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :kind, null: false
      t.integer :points, null: false
      t.string :source_type, null: false
      t.bigint :source_id, null: false
      # Context for reversals and the per-room board. No foreign keys: the
      # ledger outlives nothing, rows are deleted explicitly on reversal.
      t.bigint :post_id
      t.bigint :comment_id
      t.bigint :actor_id
      t.bigint :room_id
      # Earned on an anonymous breath: counts for the author, never on a public board.
      t.boolean :anonymous, null: false, default: false
      t.date :created_on, null: false
      t.datetime :created_at, null: false
    end

    add_index :seed_events, %i[user_id kind source_type source_id], unique: true, name: "index_seed_events_uniqueness"
    add_index :seed_events, %i[user_id kind created_on]
    add_index :seed_events, %i[created_on user_id]
    add_index :seed_events, :post_id
    add_index :seed_events, :comment_id
    add_index :seed_events, %i[source_type source_id]
    add_index :seed_events, %i[room_id created_on]

    # One row per rank a member reaches: the rank-up notification points at it.
    create_table :seed_rank_ups do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :rank_index, null: false
      t.timestamps
    end
    add_index :seed_rank_ups, %i[user_id rank_index], unique: true

    add_column :users, :seeds_total, :integer, null: false, default: 0
    # Highest rank reached (a rank-up notification goes out once per rank) and
    # the highest rank whose celebration the member has seen.
    add_column :users, :seeds_rank_reached, :integer, null: false, default: 0
    add_column :users, :seeds_rank_seen, :integer, null: false, default: 0
    add_index :users, :seeds_total
  end
end

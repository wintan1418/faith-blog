# frozen_string_literal: true

class CreateReports < ActiveRecord::Migration[8.0]
  def change
    create_table :reports do |t|
      t.references :reporter, null: false, foreign_key: { to_table: :users }
      t.references :reportable, polymorphic: true, null: false
      t.text :reason, null: false
      t.integer :status, default: 0, null: false
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.datetime :reviewed_at
      t.text :resolution_notes

      t.timestamps
    end

    add_index :reports, :status
    add_index :reports, [:reportable_type, :reportable_id, :status]
  end
end


# frozen_string_literal: true

# Breathers around you safety: every time a member's city changes we keep who,
# from where, to where and when, so the "2 changes in 30 days" limit can be
# enforced and staff can spot anyone hopping between towns to scan them.
class CreateCityChanges < ActiveRecord::Migration[8.1]
  def change
    create_table :city_changes do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :from_city, foreign_key: { to_table: :cities, on_delete: :nullify }, index: false
      t.references :to_city, foreign_key: { to_table: :cities, on_delete: :nullify }, index: false
      # false for a first city and for clearing it: those don't use up a change.
      t.boolean :counted, null: false, default: false
      t.datetime :created_at, null: false
    end
    add_index :city_changes, [ :user_id, :created_at ]
    add_index :city_changes, :created_at
  end
end

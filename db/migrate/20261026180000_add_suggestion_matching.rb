# frozen_string_literal: true

# "Brethren you may know": a public assembly on profiles, comparable keys for
# matching, and a list of suggestions people dismissed.
class AddSuggestionMatching < ActiveRecord::Migration[8.0]
  def up
    add_column :profiles, :assembly, :string, limit: 120
    add_column :profiles, :assembly_key, :string
    add_column :profiles, :city_key, :string
    add_index :profiles, :assembly_key
    add_index :profiles, :city_key

    add_column :experiences, :organization_key, :string
    add_column :experiences, :title_key, :string
    add_index :experiences, :organization_key
    add_index :experiences, :title_key

    create_table :suggestion_dismissals do |t|
      t.references :user, null: false, foreign_key: true
      t.references :dismissed_user, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :suggestion_dismissals, %i[user_id dismissed_user_id], unique: true

    # Existing locations get a city key straight away.
    execute <<~SQL.squish
      UPDATE profiles SET city_key = NULLIF(TRIM(REGEXP_REPLACE(LOWER(SPLIT_PART(location, ',', 1)), '[^a-z0-9]+', ' ', 'g')), '')
      WHERE location IS NOT NULL
    SQL
  end

  def down
    drop_table :suggestion_dismissals
    remove_column :experiences, :title_key
    remove_column :experiences, :organization_key
    remove_column :profiles, :city_key
    remove_column :profiles, :assembly_key
    remove_column :profiles, :assembly
  end
end

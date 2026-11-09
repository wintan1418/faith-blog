# frozen_string_literal: true

# Professional step 3: "Open to" (with who can see it), skill endorsements
# from connections, and a colour for the digital business card.
class AddOpenToEndorsementsAndCard < ActiveRecord::Migration[8.1]
  def change
    add_column :profiles, :open_to, :string, array: true, null: false, default: []
    add_column :profiles, :open_to_visibility, :integer, null: false, default: 0 # 0 everyone, 1 connections
    add_column :profiles, :card_style, :string, limit: 20, null: false, default: "mint"

    create_table :skill_endorsements do |t|
      t.references :user, null: false, foreign_key: true                          # who was endorsed
      t.references :endorser, null: false, foreign_key: { to_table: :users }
      t.string :skill, null: false, limit: 40                                     # as the member wrote it
      t.string :skill_key, null: false, limit: 40                                 # lower-case, for matching
      t.timestamps
    end
    add_index :skill_endorsements, [ :user_id, :endorser_id, :skill_key ], unique: true, name: "index_endorsements_unique"
    add_index :skill_endorsements, [ :user_id, :skill_key ]
  end
end

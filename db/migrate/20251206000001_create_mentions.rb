# frozen_string_literal: true

class CreateMentions < ActiveRecord::Migration[8.0]
  def change
    create_table :mentions do |t|
      t.references :user, null: false, foreign_key: true
      t.references :mentionable, null: false, polymorphic: true
      t.references :mentioned_by, null: false, polymorphic: true

      t.timestamps
    end

    add_index :mentions, [ :user_id, :mentionable_type, :mentionable_id ], name: "index_mentions_on_user_and_mentionable"
    add_index :mentions, [ :mentionable_type, :mentionable_id ]
    add_index :mentions, [ :mentioned_by_type, :mentioned_by_id ]
  end
end

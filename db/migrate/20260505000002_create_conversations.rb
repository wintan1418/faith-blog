# frozen_string_literal: true

class CreateConversations < ActiveRecord::Migration[8.0]
  def change
    create_table :conversations do |t|
      t.datetime :last_message_at
      t.timestamps
    end

    add_index :conversations, :last_message_at

    create_table :conversation_participants do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :last_read_at
      t.datetime :archived_at
      t.datetime :muted_at
      t.timestamps
    end

    add_index :conversation_participants, [ :conversation_id, :user_id ], unique: true, name: "index_conversation_participants_unique_pair"
    add_index :conversation_participants, [ :user_id, :archived_at ]

    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.references :sender, null: false, foreign_key: { to_table: :users }
      t.text :body, null: false
      t.datetime :edited_at
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :messages, [ :conversation_id, :created_at ]
    add_index :messages, [ :sender_id, :created_at ]
    add_index :messages, :deleted_at
  end
end

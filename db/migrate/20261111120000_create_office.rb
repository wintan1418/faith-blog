# frozen_string_literal: true

# The Office: the founder's AI assistant inside Admin. Conversations hold
# messages (the founder's, the assistant's, and tool results that render as
# cards). The briefing is a single row of standing context for every reply.
class CreateOffice < ActiveRecord::Migration[8.1]
  def change
    create_table :office_conversations do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false, default: "New conversation"
      t.boolean :thinking, null: false, default: false
      t.datetime :last_message_at
      t.timestamps
    end
    add_index :office_conversations, [ :user_id, :last_message_at ]

    create_table :office_messages do |t|
      t.references :office_conversation, null: false, foreign_key: true
      t.integer :role, null: false, default: 0
      t.text :content
      t.jsonb :payload, null: false, default: {}
      t.timestamps
    end

    create_table :office_briefings do |t|
      t.text :body, null: false, default: ""
      t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
  end
end

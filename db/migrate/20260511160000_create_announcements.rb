class CreateAnnouncements < ActiveRecord::Migration[8.0]
  def change
    create_table :announcements do |t|
      t.integer :kind, null: false, default: 0
      t.string  :kicker, limit: 80
      t.string  :title,  null: false, limit: 160
      t.text    :body
      t.references :user, foreign_key: true, null: true
      t.datetime :published_at
      t.datetime :expires_at
      t.timestamps
    end
    add_index :announcements, :kind
    add_index :announcements, :published_at
  end
end

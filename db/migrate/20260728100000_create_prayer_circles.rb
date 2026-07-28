# frozen_string_literal: true

class CreatePrayerCircles < ActiveRecord::Migration[8.0]
  def change
    create_table :circles do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.references :owner, null: false, foreign_key: { to_table: :users }
      t.string :invite_code, null: false
      t.integer :members_count, default: 0, null: false
      t.timestamps
    end
    add_index :circles, :slug, unique: true
    add_index :circles, :invite_code, unique: true

    create_table :circle_memberships do |t|
      t.references :circle, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :role, default: 0, null: false
      t.timestamps
    end
    add_index :circle_memberships, [ :circle_id, :user_id ], unique: true

    create_table :circle_breaths do |t|
      t.references :circle, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end
    add_index :circle_breaths, [ :circle_id, :created_at ]

    create_table :circle_prayers do |t|
      t.references :circle, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false
      t.text :details
      t.integer :status, default: 0, null: false
      t.datetime :answered_at
      t.integer :amens_count, default: 0, null: false
      t.timestamps
    end
    add_index :circle_prayers, [ :circle_id, :status ]

    create_table :circle_prayer_amens do |t|
      t.references :circle_prayer, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end
    add_index :circle_prayer_amens, [ :circle_prayer_id, :user_id ], unique: true
  end
end

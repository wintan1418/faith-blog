# frozen_string_literal: true

class CreateResources < ActiveRecord::Migration[8.0]
  def change
    create_table :resources do |t|
      t.references :user, null: false, foreign_key: true
      t.references :resource_category, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.integer :resource_type, default: 0, null: false
      t.string :url
      t.string :slug, null: false
      t.boolean :approved, default: false, null: false
      t.references :approved_by, foreign_key: { to_table: :users }
      t.datetime :approved_at
      t.integer :views_count, default: 0, null: false
      t.integer :downloads_count, default: 0, null: false
      t.boolean :featured, default: false, null: false

      t.timestamps
    end

    add_index :resources, :slug, unique: true
    add_index :resources, :resource_type
    add_index :resources, :approved
    add_index :resources, :featured
    add_index :resources, [:approved, :created_at]
  end
end


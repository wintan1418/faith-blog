# frozen_string_literal: true

class CreateResourceCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :resource_categories do |t|
      t.string :name, null: false
      t.text :description
      t.string :icon
      t.string :slug, null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :resource_categories, :slug, unique: true
    add_index :resource_categories, :position
  end
end


# frozen_string_literal: true

# Small named switches the admin can flip (e.g. "auto-activate celebration presets").
class CreateSiteSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :site_settings do |t|
      t.string :key, null: false
      t.text :value
      t.timestamps
    end
    add_index :site_settings, :key, unique: true
  end
end

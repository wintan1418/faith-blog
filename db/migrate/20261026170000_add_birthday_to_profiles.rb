# frozen_string_literal: true

class AddBirthdayToProfiles < ActiveRecord::Migration[8.0]
  def change
    add_column :profiles, :birth_month, :integer
    add_column :profiles, :birth_day, :integer
    add_column :profiles, :birth_year, :integer # optional, never shown
    add_column :profiles, :show_birthday, :boolean, null: false, default: true
    add_index :profiles, %i[birth_month birth_day]
  end
end

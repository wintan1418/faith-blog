# frozen_string_literal: true

# LinkedIn-style professional side of a profile: headline, skills, experience, education.
class CreateProfessionalProfile < ActiveRecord::Migration[8.0]
  def change
    add_column :profiles, :headline, :string, limit: 120
    add_column :profiles, :skills, :string, array: true, default: [], null: false

    create_table :experiences do |t|
      t.references :user, null: false, foreign_key: true
      t.string :title, null: false, limit: 100
      t.string :organization, null: false, limit: 100
      t.string :employment_type, limit: 30
      t.string :location, limit: 100
      t.date :start_on, null: false
      t.date :end_on
      t.boolean :current, null: false, default: false
      t.text :description
      t.timestamps
    end
    add_index :experiences, %i[user_id start_on]

    create_table :educations do |t|
      t.references :user, null: false, foreign_key: true
      t.string :school, null: false, limit: 120
      t.string :qualification, limit: 100
      t.string :field_of_study, limit: 100
      t.integer :start_year
      t.integer :end_year
      t.text :description
      t.timestamps
    end
  end
end

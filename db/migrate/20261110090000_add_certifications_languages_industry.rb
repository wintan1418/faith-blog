# frozen_string_literal: true

# Professional profiles, step 2: licenses & certifications, languages, and an
# industry on the profile (for search and suggestions later).
class AddCertificationsLanguagesIndustry < ActiveRecord::Migration[8.1]
  def change
    create_table :certifications do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false, limit: 150
      t.string :issuer, limit: 120
      t.date :issued_on
      t.date :expires_on
      t.string :credential_url, limit: 500
      t.timestamps
    end

    create_table :user_languages do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false, limit: 60
      t.integer :proficiency, null: false, default: 2
      t.timestamps
    end
    add_index :user_languages, "user_id, lower(name)", unique: true, name: "index_user_languages_on_user_and_name"

    add_column :profiles, :industry, :string, limit: 80
    add_index :profiles, :industry
  end
end

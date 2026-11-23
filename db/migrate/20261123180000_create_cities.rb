# Real places for "Breathers around you": GeoNames cities (CC BY 4.0), loaded by
# `bin/rails cities:import`. Only a city and its centre point are ever stored
# against a member, never their own coordinates.
class CreateCities < ActiveRecord::Migration[8.1]
  def change
    create_table :cities do |t|
      t.integer :geonames_id, null: false
      t.string :name, null: false
      t.string :ascii_name, null: false
      t.string :admin1_code, limit: 20
      t.string :admin1_name
      t.string :country_code, limit: 2, null: false
      t.string :country_name, null: false
      t.float :lat, null: false
      t.float :lng, null: false
      t.bigint :population, null: false, default: 0
      # Normalised names for type-ahead: "akure" plus spellings and word starts ("|akure|ikorodu|").
      t.string :search_key, null: false
      t.text :search_tokens, null: false, default: ""
      t.timestamps
    end
    add_index :cities, :geonames_id, unique: true
    add_index :cities, :search_key, opclass: :text_pattern_ops
    add_index :cities, :search_tokens, opclass: :gin_trgm_ops, using: :gin
    add_index :cities, [ :country_code, :population ]
    add_index :cities, [ :lat, :lng ]
  end
end

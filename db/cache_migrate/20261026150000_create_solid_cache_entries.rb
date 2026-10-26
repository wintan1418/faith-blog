# frozen_string_literal: true

# The production cache table was never created: Solid Cache's setup lives in
# db/cache_schema.rb, which only loads for a brand-new database, and Hatchbox
# deploys run migrations. This creates it on the next deploy (safe to re-run).
class CreateSolidCacheEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_cache_entries, if_not_exists: true do |t|
      t.binary :key, limit: 1024, null: false
      t.binary :value, limit: 536_870_912, null: false
      t.datetime :created_at, null: false
      t.integer :key_hash, limit: 8, null: false
      t.integer :byte_size, limit: 4, null: false
    end
    add_index :solid_cache_entries, :byte_size, if_not_exists: true
    add_index :solid_cache_entries, %i[key_hash byte_size], if_not_exists: true
    add_index :solid_cache_entries, :key_hash, unique: true, if_not_exists: true
  end
end

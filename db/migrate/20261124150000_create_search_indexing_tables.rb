# frozen_string_literal: true

# Admin → Search & indexing.
#   indexing_submissions    — one row per request to IndexNow or Google (the log)
#   indexing_pending_urls   — changed public URLs waiting for the next IndexNow batch
#   search_console_reports  — the last Google Search Console answers (refreshed daily)
#   seo_settings            — small values such as the generated IndexNow key
class CreateSearchIndexingTables < ActiveRecord::Migration[8.1]
  def change
    create_table :indexing_submissions do |t|
      t.string :engine, null: false
      t.string :trigger, null: false, default: "auto"
      t.integer :urls_count, null: false, default: 0
      t.jsonb :urls, null: false, default: []
      t.integer :status_code
      t.text :response
      t.datetime :submitted_at, null: false
      t.timestamps
    end
    add_index :indexing_submissions, :submitted_at
    add_index :indexing_submissions, [ :engine, :submitted_at ]

    create_table :indexing_pending_urls do |t|
      t.string :url, null: false
      t.string :source
      t.timestamps
    end
    add_index :indexing_pending_urls, :url, unique: true

    create_table :search_console_reports do |t|
      t.string :kind, null: false
      t.jsonb :data, null: false, default: {}
      t.text :error
      t.datetime :fetched_at
      t.timestamps
    end
    add_index :search_console_reports, :kind, unique: true

    create_table :seo_settings do |t|
      t.string :key, null: false
      t.text :value
      t.timestamps
    end
    add_index :seo_settings, :key, unique: true
  end
end

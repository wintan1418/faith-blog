# frozen_string_literal: true

# Scripture pages for the whole Bible: the public-domain text (KJV, WEB, BSB)
# and cross-references are loaded once by `bin/rails scripture:import`; the
# written explanations are generated once per page by ScriptureInsightJob;
# citations index which breaths quote which verses.
class CreateScriptureTables < ActiveRecord::Migration[8.1]
  def change
    create_table :scripture_verses do |t|
      t.string :translation, limit: 8, null: false
      t.integer :book, limit: 2, null: false
      t.integer :chapter, limit: 2, null: false
      t.integer :verse, limit: 2, null: false
      t.text :text, null: false
    end
    add_index :scripture_verses, %i[book chapter verse translation], unique: true, name: "index_scripture_verses_on_location"

    create_table :scripture_cross_references do |t|
      t.integer :book, limit: 2, null: false
      t.integer :chapter, limit: 2, null: false
      t.integer :verse, limit: 2, null: false
      t.integer :to_book, limit: 2, null: false
      t.integer :to_chapter, limit: 2, null: false
      t.integer :to_verse, limit: 2, null: false
      t.integer :to_chapter_end, limit: 2
      t.integer :to_verse_end, limit: 2
      t.integer :votes, null: false, default: 0
    end
    add_index :scripture_cross_references, %i[book chapter verse], name: "index_scripture_xrefs_on_location"

    create_table :scripture_citations do |t|
      t.references :post, null: false, foreign_key: { on_delete: :cascade }
      t.integer :book, limit: 2, null: false
      t.integer :chapter, limit: 2, null: false
      t.integer :verse_start, limit: 2
      t.integer :verse_end, limit: 2
      t.datetime :created_at, null: false
    end
    add_index :scripture_citations, %i[book chapter verse_start], name: "index_scripture_citations_on_location"

    create_table :scripture_insights do |t|
      t.string :reference, null: false, limit: 80
      t.string :slug, null: false, limit: 80
      t.string :summary, limit: 320
      t.text :explanation, null: false
      t.text :context, null: false
      t.jsonb :questions, null: false, default: []
      t.string :model, limit: 80
      t.datetime :generated_at, null: false
      t.timestamps
    end
    add_index :scripture_insights, :slug, unique: true
  end
end

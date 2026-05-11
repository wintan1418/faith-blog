class CreateChurchHistoryFigures < ActiveRecord::Migration[8.0]
  def change
    create_table :church_history_figures do |t|
      t.string  :name,         null: false, limit: 120
      t.string  :slug,         null: false, limit: 120
      t.integer :era,          null: false, default: 0
      t.integer :birth_year
      t.integer :death_year
      t.string  :claim,        limit: 240
      t.text    :featured_quote
      t.text    :bio              # AI-generated, cached
      t.datetime :bio_generated_at
      t.integer :sort_order,   default: 0
      t.timestamps
    end
    add_index :church_history_figures, :slug, unique: true
    add_index :church_history_figures, :era
  end
end

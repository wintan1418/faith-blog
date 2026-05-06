class CreateGoldenBreaths < ActiveRecord::Migration[8.0]
  def change
    create_table :golden_breaths do |t|
      t.text    :text,        null: false
      t.string  :author_name
      t.string  :reference
      t.string  :source_url
      t.boolean :active,      null: false, default: true
      t.integer :position,    null: false, default: 0

      t.timestamps
    end

    add_index :golden_breaths, :active
    add_index :golden_breaths, :position
  end
end

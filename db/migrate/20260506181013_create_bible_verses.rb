class CreateBibleVerses < ActiveRecord::Migration[8.0]
  def change
    create_table :bible_verses do |t|
      t.text    :text,      null: false
      t.string  :reference
      t.boolean :active,    null: false, default: true
      t.integer :position,  null: false, default: 0

      t.timestamps
    end

    add_index :bible_verses, :active
    add_index :bible_verses, :position
  end
end

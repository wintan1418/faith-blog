class CreateChurchHistoryEras < ActiveRecord::Migration[8.0]
  def change
    create_table :church_history_eras do |t|
      t.string   :slug, null: false, limit: 32
      t.text     :summary
      t.datetime :generated_at
      t.timestamps
    end
    add_index :church_history_eras, :slug, unique: true
  end
end

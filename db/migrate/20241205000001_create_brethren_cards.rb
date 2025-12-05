class CreateBrethrenCards < ActiveRecord::Migration[8.0]
  def change
    create_table :brethren_cards do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :church_or_assembly
      t.text :bio
      t.string :occupation
      t.string :whatsapp_number
      t.string :email
      t.boolean :is_complete, default: false

      t.timestamps
    end
  end
end


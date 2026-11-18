class CreateDonations < ActiveRecord::Migration[8.0]
  def change
    create_table :donations do |t|
      t.references :user, foreign_key: { on_delete: :nullify }, null: true
      t.integer :amount_minor, null: false
      t.string :currency, null: false, default: "NGN", limit: 3
      t.string :frequency, null: false, default: "one_time", limit: 16
      t.string :status, null: false, default: "pending", limit: 16
      t.string :reference, null: false
      t.string :email, null: false
      t.string :name
      t.boolean :anonymous, null: false, default: false
      t.text :message
      t.string :paystack_plan_code
      t.datetime :paid_at
      t.timestamps
    end
    add_index :donations, :reference, unique: true
    add_index :donations, [ :status, :paid_at ]
  end
end

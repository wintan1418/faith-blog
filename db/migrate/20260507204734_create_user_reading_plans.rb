class CreateUserReadingPlans < ActiveRecord::Migration[8.0]
  def change
    create_table :user_reading_plans do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :plan_slug, null: false
      t.integer :current_day, null: false, default: 1
      t.date    :started_on
      t.date    :last_completed_on
      t.boolean :completed, null: false, default: false

      t.timestamps
    end

    add_index :user_reading_plans, [ :user_id, :plan_slug ], unique: true
  end
end

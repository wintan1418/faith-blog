# frozen_string_literal: true

# A writer's multi-part series ("The Gospel and Material Prosperity", parts
# 1–3). A breath belongs to at most one series, so membership lives on the
# post itself: series_id plus its place in the series (series_position).
class CreateSeries < ActiveRecord::Migration[8.1]
  def change
    create_table :series do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string :title, null: false
      t.string :slug, null: false
      t.string :description
      t.timestamps
    end
    add_index :series, :slug, unique: true

    add_reference :posts, :series, foreign_key: { on_delete: :nullify }, index: true
    add_column :posts, :series_position, :integer
  end
end

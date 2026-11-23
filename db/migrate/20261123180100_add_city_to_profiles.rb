# A member's city (never their coordinates), whether they appear in
# "Breathers around you" (off until they choose it), and who may see the city.
class AddCityToProfiles < ActiveRecord::Migration[8.1]
  def change
    add_reference :profiles, :city, foreign_key: { on_delete: :nullify }, index: true
    add_column :profiles, :show_in_nearby, :boolean, default: false, null: false
    add_column :profiles, :city_visibility, :integer, default: 0, null: false
    add_index :profiles, :show_in_nearby, where: "show_in_nearby"
  end
end

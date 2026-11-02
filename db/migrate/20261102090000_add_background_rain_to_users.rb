# frozen_string_literal: true

# Members can switch the drifting scripture "rain" behind every page off.
class AddBackgroundRainToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :background_rain, :boolean, default: true, null: false
  end
end

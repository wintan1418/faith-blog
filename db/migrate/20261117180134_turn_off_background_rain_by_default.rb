# The redesign drops the faint verses that drift behind the pages (they ran
# into cards and text). Off for everyone; members can switch it back on from
# their menu.
class TurnOffBackgroundRainByDefault < ActiveRecord::Migration[8.1]
  def up
    change_column_default :users, :background_rain, from: true, to: false
    execute "UPDATE users SET background_rain = FALSE"
  end

  def down
    change_column_default :users, :background_rain, from: false, to: true
  end
end

class MakePostRoomOptional < ActiveRecord::Migration[8.0]
  def change
    change_column_null :posts, :room_id, true
  end
end

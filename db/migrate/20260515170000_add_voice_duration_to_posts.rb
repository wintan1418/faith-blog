class AddVoiceDurationToPosts < ActiveRecord::Migration[8.0]
  def change
    add_column :posts, :voice_duration_ms, :integer
  end
end

class CreateAppReleases < ActiveRecord::Migration[8.1]
  def change
    create_table :app_releases do |t|
      t.string :platform, null: false
      t.string :latest_version
      t.string :minimum_version
      t.datetime :reminded_at
      t.timestamps
    end
    add_index :app_releases, :platform, unique: true

    # The app version each member last opened Brethreign with, so admins can see who is behind.
    add_column :users, :android_app_version, :string
    add_index :users, :android_app_version
  end
end

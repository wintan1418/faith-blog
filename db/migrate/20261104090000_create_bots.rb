# The Updates tab: bots that bring in news, sports, jobs and free courses
# from trusted feeds. Bot items live apart from members' breaths, so they never
# show up in Recent, Trending, notifications or anyone's profile.
class CreateBots < ActiveRecord::Migration[8.0]
  def change
    create_table :bot_sources do |t|
      t.string :bot, null: false          # news / sports / jobs / courses
      t.string :topic                     # world, politics, tech, science…
      t.string :name, null: false         # shown on the card ("BBC News")
      t.string :url, null: false
      t.string :format, null: false, default: "rss" # rss (also Atom/RDF), remotive, himalayas
      t.boolean :active, null: false, default: true
      t.datetime :last_fetched_at
      t.string :last_error
      t.timestamps
    end
    add_index :bot_sources, :url, unique: true
    add_index :bot_sources, [ :bot, :active ]

    create_table :bot_items do |t|
      t.references :bot_source, null: false, foreign_key: true
      t.string :bot, null: false
      t.string :topic
      t.string :title, null: false
      t.text :summary
      t.string :url, null: false
      t.string :url_digest, null: false
      t.string :image_url
      t.jsonb :details, null: false, default: {} # company, location, salary…
      t.integer :status, null: false, default: 0 # live / hidden / skipped
      t.string :skip_reason
      t.integer :likes_count, null: false, default: 0
      t.datetime :published_at, null: false
      t.timestamps
    end
    add_index :bot_items, :url_digest, unique: true
    add_index :bot_items, [ :status, :bot, :published_at ]
    add_index :bot_items, [ :status, :published_at ]

    # Bots a member has switched off in their Updates tab.
    add_column :users, :hidden_bots, :string, array: true, null: false, default: []
  end
end

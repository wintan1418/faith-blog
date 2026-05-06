class AddReactionEmojiToLikes < ActiveRecord::Migration[8.0]
  def up
    add_column :likes, :reaction_emoji, :string

    enum_to_emoji = { 0 => "🙏", 1 => "✝️", 2 => "💪", 3 => "❤️", 4 => "✨" }
    enum_to_emoji.each do |int, emoji|
      execute(
        "UPDATE likes SET reaction_emoji = #{ActiveRecord::Base.connection.quote(emoji)} " \
        "WHERE reaction_type = #{int} AND reaction_emoji IS NULL"
      )
    end

    add_index :likes, [ :likeable_type, :likeable_id, :reaction_emoji ],
              name: "index_likes_on_likeable_and_emoji"
  end

  def down
    remove_index :likes, name: "index_likes_on_likeable_and_emoji"
    remove_column :likes, :reaction_emoji
  end
end

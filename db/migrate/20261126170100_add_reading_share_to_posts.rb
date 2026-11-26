# frozen_string_literal: true

# "Read your Bible, pray every day" shared to the feed: the chapter, the key
# verse (text as shared), today's prayer burden, notes the member chose to
# include and their streak. Built and sanitised on the server
# (Post.build_reading_share); nil for every other breath.
class AddReadingShareToPosts < ActiveRecord::Migration[8.1]
  def change
    add_column :posts, :reading_share, :jsonb
  end
end

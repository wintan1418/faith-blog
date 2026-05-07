class AllowNullTitleOnPosts < ActiveRecord::Migration[8.0]
  def change
    change_column_null :posts, :title, true
  end
end

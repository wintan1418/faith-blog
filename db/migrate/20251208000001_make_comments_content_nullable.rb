# frozen_string_literal: true

class MakeCommentsContentNullable < ActiveRecord::Migration[8.0]
  def change
    # ActionText stores content in action_text_rich_texts table, not in comments.content
    # So we need to make this column nullable
    change_column_null :comments, :content, true
  end
end

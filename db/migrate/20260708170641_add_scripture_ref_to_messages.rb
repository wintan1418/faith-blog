class AddScriptureRefToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :scripture_ref, :string
  end
end

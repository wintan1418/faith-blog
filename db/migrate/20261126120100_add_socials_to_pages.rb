# frozen_string_literal: true

# A page's own social accounts ({ "x" => "https://x.com/…", "instagram" => … }),
# shown as a "Follow" row on its About tab.
class AddSocialsToPages < ActiveRecord::Migration[8.1]
  def change
    add_column :pages, :socials, :jsonb, null: false, default: {}
  end
end

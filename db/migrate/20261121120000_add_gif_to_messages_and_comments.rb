# A GIF picked from Klipy: we keep only its address on Klipy's media CDN, its
# size (so the bubble keeps its shape before it loads) and its title (alt text).
class AddGifToMessagesAndComments < ActiveRecord::Migration[8.1]
  def change
    %i[messages comments].each do |table|
      add_column table, :gif_url, :string
      add_column table, :gif_width, :integer
      add_column table, :gif_height, :integer
      add_column table, :gif_title, :string
    end
  end
end

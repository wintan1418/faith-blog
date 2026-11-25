# frozen_string_literal: true

# Pages: churches, ministries, fellowships, businesses, schools, NGOs and
# communities on Brethreign (like LinkedIn Company Pages). A page has people
# who run it (page_memberships), followers (page_follows), and posts written
# by its editors but shown as the page (posts.page_id; the writer stays in
# posts.user_id for moderation and audit).
class CreatePages < ActiveRecord::Migration[8.1]
  def change
    create_table :pages do |t|
      t.string :name, null: false, limit: 80
      t.string :handle, null: false, limit: 30
      t.integer :category, null: false, default: 0
      t.string :tagline, limit: 160
      t.text :about
      t.string :website, limit: 255
      t.string :email, limit: 255
      t.string :phone, limit: 40
      t.references :city, foreign_key: { on_delete: :nullify }
      t.string :location, limit: 100
      t.integer :founded_year
      t.string :size_range, limit: 20
      t.string :tradition, limit: 120
      t.text :service_times
      # Verification (admin only) and the page's request for it.
      t.datetime :verified_at
      t.references :verified_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.integer :verification_status, null: false, default: 0
      t.text :verification_note
      t.datetime :verification_requested_at
      t.integer :status, null: false, default: 0
      t.datetime :suspended_at
      # The tier ("Pro pages" later). Everything is free for now.
      t.integer :plan, null: false, default: 0
      t.integer :followers_count, null: false, default: 0
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.tsvector :searchable
      t.timestamps
    end
    add_index :pages, "lower(handle)", unique: true, name: "index_pages_on_lower_handle"
    add_index :pages, %i[status category]
    add_index :pages, :searchable, using: :gin
    add_index :pages, :verification_status, where: "verification_status = 1", name: "index_pages_verification_requested"

    create_table :page_memberships do |t|
      t.references :page, null: false, foreign_key: { on_delete: :cascade }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.integer :role, null: false, default: 2
      t.integer :status, null: false, default: 0
      t.references :invited_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.datetime :accepted_at
      t.timestamps
    end
    add_index :page_memberships, %i[page_id user_id], unique: true
    add_index :page_memberships, %i[user_id status role]

    create_table :page_follows do |t|
      t.references :page, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end
    add_index :page_follows, %i[page_id user_id], unique: true
    add_index :page_follows, %i[page_id created_at]
  end
end

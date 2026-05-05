# frozen_string_literal: true

class AddEmailNotificationsToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :email_notifications_enabled, :boolean, null: false, default: true
  end
end

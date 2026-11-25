# frozen_string_literal: true

# Devices & sessions (AccountDevices): record each sign-in on the device it
# came from, and end that device's session on sign-out.
Warden::Manager.after_set_user except: :fetch do |record, warden, options|
  next unless options[:scope] == :user && record.is_a?(User) && options[:store] != false

  request = ActionDispatch::Request.new(warden.env)
  remembered = warden.winning_strategy.is_a?(Devise::Strategies::Rememberable)
  AccountDevices.signed_in!(record, request, strategy: remembered ? :rememberable : nil)
end

Warden::Manager.before_logout do |record, warden, options|
  next unless options[:scope] == :user && record.is_a?(User)

  AccountDevices.signed_out!(record, ActionDispatch::Request.new(warden.env))
end

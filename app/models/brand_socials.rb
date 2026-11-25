# frozen_string_literal: true

# Brethreign's own social accounts, from config/socials.yml.
#   BrandSocials.all        # => [#<Account key="x" label="X" handle="@_Brethreign_" url="https://x.com/…">, …]
#   BrandSocials.same_as    # => the profile URLs (no email), for JSON-LD "sameAs"
module BrandSocials
  Account = Data.define(:key, :label, :handle, :url) do
    def email? = key == "email"
  end

  module_function

  def all
    @all ||= YAML.safe_load_file(Rails.root.join("config/socials.yml")).map do |key, attrs|
      Account.new(key: key.to_s, label: attrs["label"].to_s, handle: attrs["handle"].to_s, url: attrs["url"].to_s)
    end.freeze
  end

  def profiles = all.reject(&:email?)

  def find(key) = all.find { |a| a.key == key.to_s }

  def same_as = profiles.map(&:url)

  def email = find(:email)&.handle
end

# frozen_string_literal: true

require "cloudinary"

cloudinary_url = ENV["CLOUDINARY_URL"]
credentials = Rails.application.credentials

if cloudinary_url.present?
  Cloudinary.config_from_url(cloudinary_url)
else
  cloud_name = credentials.dig(:cloudinary, :cloud_name) || ENV["CLOUDINARY_CLOUD_NAME"]
  api_key = credentials.dig(:cloudinary, :api_key) || ENV["CLOUDINARY_API_KEY"]
  api_secret = credentials.dig(:cloudinary, :api_secret) || ENV["CLOUDINARY_API_SECRET"]

  Cloudinary.config do |config|
    config.cloud_name = cloud_name if cloud_name.present?
    config.api_key = api_key if api_key.present?
    config.api_secret = api_secret if api_secret.present?
    config.secure = true
  end
end

if Rails.application.config.active_storage.service.to_sym == :cloudinary
  missing = []
  missing << "cloud_name" if Cloudinary.config.cloud_name.blank?
  missing << "api_key" if Cloudinary.config.api_key.blank?
  missing << "api_secret" if Cloudinary.config.api_secret.blank?
  placeholders = []
  placeholders << "cloud_name" if Cloudinary.config.cloud_name.to_s.match?(/\A(CLOUD_NAME|your_cloud_name)\z/i)
  placeholders << "api_key" if Cloudinary.config.api_key.to_s.match?(/\A(API_KEY|your_api_key)\z/i)
  placeholders << "api_secret" if Cloudinary.config.api_secret.to_s.match?(/\A(API_SECRET|your_api_secret)\z/i)

  if missing.any?
    raise "Cloudinary Active Storage is enabled but missing #{missing.join(', ')}. " \
          "Set CLOUDINARY_URL or CLOUDINARY_CLOUD_NAME/CLOUDINARY_API_KEY/CLOUDINARY_API_SECRET."
  end

  if placeholders.any?
    raise "Cloudinary Active Storage is enabled but #{placeholders.join(', ')} still uses a placeholder value. " \
          "Replace CLOUDINARY_URL with the real value from the Cloudinary dashboard."
  end
end

require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on Cloudinary (see config/storage.yml for options).
  # For local development, use :local. For production, use :cloudinary
  config.active_storage.service = ENV.fetch("RAILS_STORAGE_SERVICE", "cloudinary").to_sym

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  config.force_ssl = true

  # Skip http-to-https redirect for the default health check endpoint.
  # config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Change to "debug" to log everything (including potentially personally-identifiable information!)
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # Email configuration
  # Set this to true to raise delivery errors in production
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.perform_deliveries = true
  config.action_mailer.delivery_method = :smtp

  # Set host to be used by links generated in mailer templates.
  # Update this with your actual domain
  config.action_mailer.default_url_options = { 
    host: ENV.fetch("RAILS_HOST", "yourdomain.com"),
    protocol: "https"
  }

  # SMTP configuration
  # Credentials can be set via Rails credentials or environment variables
  # To set via credentials: rails credentials:edit
  # Add: smtp:
  #        user_name: your_email@example.com
  #        password: your_password
  #        address: smtp.example.com
  #        domain: yourdomain.com
  config.action_mailer.smtp_settings = {
    address: Rails.application.credentials.dig(:smtp, :address) || ENV.fetch("SMTP_ADDRESS", "smtp.gmail.com"),
    port: Rails.application.credentials.dig(:smtp, :port) || ENV.fetch("SMTP_PORT", "587").to_i,
    domain: Rails.application.credentials.dig(:smtp, :domain) || ENV.fetch("SMTP_DOMAIN", "yourdomain.com"),
    user_name: Rails.application.credentials.dig(:smtp, :user_name) || ENV["SMTP_USER_NAME"],
    password: Rails.application.credentials.dig(:smtp, :password) || ENV["SMTP_PASSWORD"],
    authentication: Rails.application.credentials.dig(:smtp, :authentication) || ENV.fetch("SMTP_AUTH", "plain").to_sym,
    enable_starttls_auto: true,
    openssl_verify_mode: "none" # Use "peer" in production with proper SSL
  }

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
end

# frozen_string_literal: true

# A page that crashes (500) alerts the admins straight away (ErrorAlert), so a
# broken page is found by us, not by members.
Rails.application.config.after_initialize do
  next unless Rails.env.production? || ENV["ERROR_ALERTS"] == "1"

  ActiveSupport::Notifications.subscribe("process_action.action_controller") do |event|
    error = event.payload[:exception_object]
    next unless error
    next if ActionDispatch::ExceptionWrapper.status_code_for_exception(error.class.name) < 500

    where = Array(error.backtrace).find { |line| line.include?("/app/") }.to_s.sub(%r{\A.*?/app/}, "app/")
    path = event.payload[:path].to_s.split("?").first
    ErrorAlert.notify(
      key: "#{error.class}|#{where}",
      title: "#{path} is crashing (#{error.class.name.demodulize})",
      detail: "Page: #{event.payload[:method]} #{path}\nError: #{error.class}: #{error.message.to_s.truncate(500)}\nWhere: #{where}\nTime: #{Time.current.utc.iso8601}"
    )
  end
end

# After each deploy: check the main pages a minute after the app boots.
Rails.application.config.after_initialize do
  next unless Rails.env.production? && defined?(Rails::Server)

  SiteHealthCheckJob.set(wait: 90.seconds).perform_later
rescue StandardError => e
  Rails.logger.warn("[SiteHealthCheck] couldn't schedule the after-deploy check: #{e.class}: #{e.message}")
end

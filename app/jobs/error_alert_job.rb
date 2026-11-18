# frozen_string_literal: true

# Sends one ErrorAlert: an email to every admin and a push to their phones.
class ErrorAlertJob < ApplicationJob
  queue_as :default

  def perform(title, detail, count)
    admins = ErrorAlert.recipients.to_a
    return if admins.empty?

    AdminAlertMailer.problem(emails: admins.map(&:email), title: title, detail: detail, count: count).deliver_now
    body = count > 1 ? "#{title} (#{count} times)" : title
    admins.each do |admin|
      admin.push_devices.find_each do |device|
        ApplicationPushNotification.new(title: "Brethreign problem", body: body.truncate(150),
                                        sound: "default", data: { path: "/admin" }).deliver_to(device)
      rescue StandardError => e
        Rails.logger.warn("[ErrorAlertJob] push failed: #{e.class}: #{e.message}")
      end
    end
  end
end

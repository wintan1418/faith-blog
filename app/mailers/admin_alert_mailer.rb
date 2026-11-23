# frozen_string_literal: true

class AdminAlertMailer < ApplicationMailer
  def problem(emails:, title:, detail:, count:)
    @title = title
    @detail = detail
    @count = count
    mail(to: emails, subject: "[Brethreign] #{title}")
  end

  def daily_summary(emails:, date:, bots:, stats:)
    @date = date
    @bots = bots
    @stats = stats
    mail(to: emails, subject: "[Brethreign] Daily summary · #{date.strftime('%a %-d %b')}")
  end
end

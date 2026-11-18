# frozen_string_literal: true

class AdminAlertMailer < ApplicationMailer
  def problem(emails:, title:, detail:, count:)
    @title = title
    @detail = detail
    @count = count
    mail(to: emails, subject: "[Brethreign] #{title}")
  end
end

# frozen_string_literal: true

# Standing context for the Office assistant, sent with every reply: who the
# founder is, how to write, what is going on. One row, edited in Admin → Office.
class OfficeBriefing < ApplicationRecord
  DEFAULT_PATH = Rails.root.join("config/office/briefing.md")
  MAX_LENGTH = 40_000

  belongs_to :updated_by, class_name: "User", optional: true

  validates :body, length: { maximum: MAX_LENGTH }

  # The briefing, created from the default file the first time it's needed.
  def self.current
    first || create!(body: default_body)
  end

  def self.default_body
    File.exist?(DEFAULT_PATH) ? File.read(DEFAULT_PATH) : ""
  end
end

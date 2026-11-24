# frozen_string_literal: true

# One request we made to a search engine: an IndexNow batch or a Google
# sitemap submit. Shown in Admin → Search & indexing as the submission log.
class IndexingSubmission < ApplicationRecord
  ENGINES = %w[indexnow google_sitemap].freeze
  TRIGGERS = %w[auto manual nightly].freeze
  URLS_KEPT = 50 # a sample of what was sent, so the log stays small
  RESPONSE_KEPT = 2_000

  validates :engine, inclusion: { in: ENGINES }
  validates :trigger, inclusion: { in: TRIGGERS }

  scope :recent, -> { order(submitted_at: :desc) }
  scope :since, ->(time) { where(submitted_at: time..) }

  def self.log!(engine:, urls:, status_code:, response:, trigger: "auto")
    create!(engine: engine, trigger: trigger, urls_count: urls.size, urls: urls.first(URLS_KEPT),
            status_code: status_code, response: response.to_s.first(RESPONSE_KEPT), submitted_at: Time.current)
  end

  def success?
    status_code.to_i.between?(200, 299)
  end

  def engine_label
    engine == "indexnow" ? "IndexNow" : "Google sitemap"
  end

  # What the status code means, in words (IndexNow documents its codes).
  def status_label
    case status_code
    when nil then "No answer"
    when 200 then "OK"
    when 202 then "Accepted (key check pending)"
    when 204 then "OK"
    when 400 then "Bad request"
    when 403 then "Key not valid"
    when 422 then "URLs don't match the host"
    when 429 then "Too many requests"
    else "HTTP #{status_code}"
    end
  end
end

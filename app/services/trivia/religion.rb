# frozen_string_literal: true

require "net/http"
require "json"
require "uri"
require "cgi"

module Trivia
  # Religion trivia from Open Trivia DB (category 20). No auth needed,
  # rate-limited per IP; we keep batch size modest.
  module Religion
    class Error < StandardError; end

    ENDPOINT = "https://opentdb.com/api.php"

    def self.fetch_batch(count = 5)
      uri = URI(ENDPOINT)
      uri.query = URI.encode_www_form(amount: count, category: 20, type: "multiple")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 4
      http.read_timeout = 5

      response = http.request(Net::HTTP::Get.new(uri))
      raise Error, "bad status #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      payload = JSON.parse(response.body)
      raise Error, "response_code=#{payload["response_code"]}" unless payload["response_code"] == 0

      Array(payload["results"]).map { |q| normalize(q) }.compact
    rescue StandardError => e
      raise Error, e.message unless e.is_a?(Error)
      raise
    end

    def self.normalize(raw)
      decoded_q = CGI.unescapeHTML(raw["question"].to_s)
      correct   = CGI.unescapeHTML(raw["correct_answer"].to_s)
      incorrect = Array(raw["incorrect_answers"]).map { |a| CGI.unescapeHTML(a.to_s) }
      return nil if decoded_q.blank? || correct.blank? || incorrect.empty?

      choices = (incorrect + [ correct ]).shuffle
      {
        kind:          "trivia",
        prompt:        decoded_q,
        choices:       choices,
        correct_index: choices.index(correct) || 0,
        reference:     "",
        explanation:   raw["difficulty"].present? ? "Difficulty: #{raw["difficulty"]}" : ""
      }
    end
  end
end

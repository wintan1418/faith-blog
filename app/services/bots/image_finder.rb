# frozen_string_literal: true

module Bots
  # The picture an article sets for link previews (og:image), for feeds that
  # don't include one. Only called for the few items actually posted.
  module ImageFinder
    module_function

    def call(url)
      html = Http.get(url, accept: "text/html")
      doc = Nokogiri::HTML(html.byteslice(0, 300_000))
      found = doc.at_css("meta[property='og:image']")&.[]("content") ||
              doc.at_css("meta[name='twitter:image']")&.[]("content")
      found = URI.join(url, found).to_s if found.present?
      found if found.to_s.start_with?("https://")
    rescue Http::Error, URI::Error, ArgumentError
      nil
    end
  end
end

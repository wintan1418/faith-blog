# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

# Resolve Bible references like "John 3:16" or "1 Cor 13:4-7" to text
# via bible-api.com. Free, no key. Cached aggressively because verses
# don't change.
class ScriptureLookup
  ENDPOINT    = "https://bible-api.com"
  TRANSLATION = "kjv"
  TIMEOUT     = 4
  CACHE_TTL   = 7.days

  REFERENCE_REGEX = /
    \b
    (?<book>
      (?:[1-3]\s?)?
      (?:Gen(?:esis)?|Exo(?:dus)?|Lev(?:iticus)?|Num(?:bers)?|Deut(?:eronomy)?|
         Josh(?:ua)?|Judg(?:es)?|Ruth|Sam(?:uel)?|Kings|Chron(?:icles)?|
         Ezra|Neh(?:emiah)?|Esth(?:er)?|Job|Ps(?:alm[s]?)?|Prov(?:erbs)?|
         Eccl(?:esiastes)?|Song(?:\sof\s(?:Songs|Solomon))?|Isa(?:iah)?|
         Jer(?:emiah)?|Lam(?:entations)?|Ezek(?:iel)?|Dan(?:iel)?|Hos(?:ea)?|
         Joel|Amos|Obad(?:iah)?|Jon(?:ah)?|Mic(?:ah)?|Nah(?:um)?|Hab(?:akkuk)?|
         Zeph(?:aniah)?|Hag(?:gai)?|Zech(?:ariah)?|Mal(?:achi)?|
         Matt(?:hew)?|Mark|Luke|John|Acts|Rom(?:ans)?|Cor(?:inthians)?|
         Gal(?:atians)?|Eph(?:esians)?|Phil(?:ippians)?|Col(?:ossians)?|
         Thess(?:alonians)?|Tim(?:othy)?|Tit(?:us)?|Phil(?:emon)?|Heb(?:rews)?|
         Jas|James|Pet(?:er)?|Jude|Rev(?:elation)?)
    )
    \s+
    (?<chapter>\d{1,3})
    (?:
      :
      (?<verse>\d{1,3})
      (?:[-–]
        (?<verse_end>\d{1,3})
      )?
    )?
    \b
  /xi.freeze

  def self.find_references(text)
    return [] if text.blank?

    text.to_s.scan(REFERENCE_REGEX).map do
      Regexp.last_match[0]
    end.uniq
  end

  def self.lookup(reference)
    key = "scripture:#{TRANSLATION}:#{reference.to_s.strip.downcase}"
    cached = (Rails.cache.read(key) rescue nil)
    return cached if cached

    text = fetch(reference)
    if text
      begin
        Rails.cache.write(key, text, expires_in: CACHE_TTL)
      rescue StandardError
        # Cache backend unavailable — that's fine, just don't memoize.
      end
    end
    text
  end

  def self.fetch(reference)
    encoded = URI.encode_www_form_component(reference.to_s.strip)
    uri = URI("#{ENDPOINT}/#{encoded}?translation=#{TRANSLATION}")

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = TIMEOUT
    http.read_timeout = TIMEOUT

    response = http.request(Net::HTTP::Get.new(uri))
    return nil unless response.is_a?(Net::HTTPSuccess)

    payload = JSON.parse(response.body)
    {
      reference: payload["reference"],
      text: payload["text"].to_s.strip,
      translation: payload["translation_name"] || "KJV"
    }
  rescue StandardError => e
    Rails.logger.warn "[scripture] lookup failed for #{reference.inspect}: #{e.message}"
    nil
  end
end

# frozen_string_literal: true

module Bots
  # Turns a source's feed (RSS, Atom, RDF, or a job board's JSON) into plain
  # candidates. Nothing here decides what gets posted; Bots::Editor does.
  class Reader
    Candidate = Struct.new(:title, :url, :text, :image_url, :published_at, :details, keyword_init: true)

    def self.call(source, body = nil) = new(source).call(body)

    def initialize(source)
      @source = source
    end

    def call(body = nil)
      body ||= Http.get(@source.url, accept: accept)
      entries = case @source.format
      when "remotive"  then remotive(JSON.parse(body))
      when "himalayas" then himalayas(JSON.parse(body))
      else feed(body)
      end
      entries.select { |c| c.title.present? && c.url.to_s.start_with?("https://") }
    end

    private

    def accept
      @source.format == "rss" ? "application/rss+xml, application/atom+xml, application/xml, text/xml" : "application/json"
    end

    # RSS 2.0, Atom and RDF all reduce to items/entries once namespaces go.
    def feed(body)
      doc = Nokogiri::XML(body) { |config| config.recover.nonet }
      raw = body # keep namespaced lookups for media:* before stripping
      media = Nokogiri::XML(raw) { |config| config.recover.nonet }
      doc.remove_namespaces!

      nodes = doc.xpath("//item | //entry")
      media_nodes = media.xpath("//*[local-name()='item' or local-name()='entry']")

      nodes.each_with_index.map do |node, i|
        link = node.at_xpath("link[@rel='alternate']/@href | link/@href")&.value.presence || node.at_xpath("link")&.text
        # media:content is also "content" once namespaces go, so ask in order.
        html = %w[encoded description summary content].lazy.map { |tag| node.at_xpath(tag)&.text.presence }.find(&:itself)
        title = clean(node.at_xpath("title")&.text)
        details = {}
        # Job feeds (We Work Remotely): "Company: Role", plus region and type.
        if (region = node.at_xpath("region")&.text.presence)
          company, role = title.split(/:\s+/, 2)
          title = role if role.present?
          details = job_details(role.present? ? company : nil, region, nil, node.at_xpath("type")&.text)
          html = html.to_s.sub(%r{\A.*?</p>}m, "") if html.to_s.include?("Headquarters:")
        end
        Candidate.new(
          title: title,
          url: link.to_s.strip,
          text: clean(html).truncate(600),
          image_url: image_from(media_nodes[i], html),
          published_at: time_from(node.at_xpath("pubDate | published | updated | date")&.text),
          details: details
        )
      end
    end

    def image_from(node, html)
      url = node&.at_xpath(".//*[local-name()='content' and starts-with(@medium,'image')]/@url")&.value ||
            node&.at_xpath(".//*[local-name()='content' and @url and (not(@type) or starts-with(@type,'image'))]/@url")&.value ||
            node&.at_xpath(".//*[local-name()='thumbnail']/@url")&.value ||
            node&.at_xpath(".//*[local-name()='enclosure' and starts-with(@type,'image')]/@url")&.value ||
            html.to_s[/<img[^>]+src=["']([^"']+)["']/i, 1]
      https(url)
    end

    def remotive(json)
      Array(json["jobs"]).map do |job|
        Candidate.new(
          title: clean(job["title"]), url: job["url"].to_s,
          text: clean(job["description"]).truncate(600),
          image_url: https(job["company_logo"]),
          published_at: time_from(job["publication_date"]),
          details: job_details(job["company_name"], job["candidate_required_location"], job["salary"], job["job_type"])
        )
      end
    end

    def himalayas(json)
      Array(json["jobs"]).map do |job|
        Candidate.new(
          title: clean(job["title"]), url: (job["applicationLink"].presence || job["guid"]).to_s,
          text: clean(job["excerpt"].presence || job["description"]).truncate(600),
          image_url: https(job["companyLogo"]),
          published_at: job["pubDate"].is_a?(Numeric) ? Time.zone.at(job["pubDate"]) : time_from(job["pubDate"]),
          details: job_details(job["companyName"], Array(job["locationRestrictions"]).join(", ").presence || "Anywhere",
                               salary(job["minSalary"], job["maxSalary"], job["currency"]), job["employmentType"])
        )
      end
    end

    def job_details(company, location, salary, type)
      { "company" => clean(company).presence, "location" => clean(location).presence,
        "salary" => clean(salary).presence, "type" => clean(type).presence }.compact
    end

    def salary(min, max, currency)
      return if min.blank? && max.blank?
      [ min, max ].compact.map { |n| n.to_i >= 1000 ? "#{(n.to_i / 1000.0).round}k" : n.to_s }.join("–").then { |s| "#{currency} #{s}".strip }
    end

    def clean(value)
      text = Nokogiri::HTML.fragment(value.to_s).text
      CGI.unescapeHTML(text).gsub(/\s+/, " ").strip
    end

    def https(url)
      url = url.to_s.strip.sub(%r{\Ahttp://}i, "https://")
      url.start_with?("https://") ? url : nil
    end

    def time_from(value)
      Time.zone.parse(value.to_s) || Time.current
    rescue ArgumentError
      Time.current
    end
  end
end

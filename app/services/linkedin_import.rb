# frozen_string_literal: true

require "csv"

# "Import from LinkedIn". LinkedIn doesn't let other apps read work history
# through its API, so members bring a file instead:
#
#   * the profile PDF (LinkedIn profile → More → Save to PDF): instant. Its
#     text is pulled out with pdf-reader and the AI sorts it into sections.
#   * the data export ZIP (Settings → Data privacy → Get a copy of your data):
#     arrives by email; its CSV files are read directly, no AI.
#
# Both give a Draft. Nothing is saved here: the member reviews the draft and
# picks what to add. The uploaded file is never stored.
module LinkedinImport
  class Error < StandardError; end

  MAX_UPLOAD = 30.megabytes
  MAX_CSV_ENTRY = 3.megabytes
  MAX_PDF_PAGES = 30
  MAX_PDF_TEXT = 16_000
  LIMITS = { positions: 30, educations: 15, certifications: 30, languages: 15, skills: Profile::MAX_SKILLS }.freeze

  Draft = Struct.new(:headline, :summary, :industry, :location, :positions, :educations, :skills,
                     :certifications, :languages, keyword_init: true) do
    def empty?
      [ headline, summary, industry ].all?(&:blank?) && [ positions, educations, skills, certifications, languages ].all?(&:blank?)
    end
  end

  # upload: an ActionDispatch::Http::UploadedFile (or anything with #path/#size).
  def self.read(upload)
    raise Error, "Choose your LinkedIn PDF or data export ZIP first." if upload.blank?
    raise Error, "That file is too big. The limit is #{MAX_UPLOAD / 1.megabyte} MB." if upload.size.to_i > MAX_UPLOAD

    head = File.binread(upload.path, 4).to_s
    draft =
      if head.start_with?("%PDF") then PdfReader.new(upload.path).call
      elsif head.start_with?("PK") then ExportReader.new(upload.path).call
      else raise Error, "That isn't a LinkedIn PDF or ZIP. Use “Save to PDF” on your LinkedIn profile, or your data export."
      end
    raise Error, "We couldn't find any profile details in that file." if draft.empty?

    draft
  end

  # ── Cleaning (shared) ────────────────────────────────────────────
  module Clean
    module_function

    def text(value, max)
      value.to_s.gsub(/[[:cntrl:]&&[^\n]]/, " ").squish.first(max).presence
    end

    def paragraph(value, max)
      value.to_s.gsub("\r\n", "\n").gsub(/[[:cntrl:]&&[^\n]]/, " ").strip.gsub(/\n{3,}/, "\n\n").first(max).presence
    end

    # "Mar 2020", "2020-03", "March 2020", "2020" → first of the month.
    def month(value)
      s = value.to_s.strip
      return nil if s.blank? || s.match?(/present|now|current/i)
      return Date.new(Regexp.last_match(1).to_i, Regexp.last_match(2).to_i, 1) if s =~ /\A(\d{4})-(\d{1,2})/
      return Date.new(s.to_i, 1, 1) if s.match?(/\A\d{4}\z/)

      Date.strptime(s, "%b %Y")
    rescue Date::Error, ArgumentError
      begin
        Date.strptime(s, "%B %Y")
      rescue Date::Error, ArgumentError
        nil
      end
    end

    def year(value)
      y = value.to_s[/\d{4}/].to_i
      y.between?(1940, Date.current.year + 8) ? y : nil
    end

    def https(value)
      url = value.to_s.strip
      url.match?(%r{\Ahttps://\S+\z}i) ? url.first(500) : nil
    end

    def position(title:, organization:, location: nil, description: nil, start_on: nil, end_on: nil, current: nil, employment_type: nil)
      title = text(title, 100)
      organization = text(organization, 100)
      return nil unless title && organization && start_on

      current = end_on.nil? if current.nil?
      { "title" => title, "organization" => organization, "location" => text(location, 100),
        "description" => paragraph(description, 2000), "start_on" => start_on.iso8601,
        "end_on" => (current ? nil : end_on&.iso8601), "current" => current,
        "employment_type" => (Experience::EMPLOYMENT_TYPES.include?(employment_type) ? employment_type : nil) }
    end

    def education(school:, qualification: nil, field_of_study: nil, start_year: nil, end_year: nil)
      school = text(school, 120)
      return nil unless school

      { "school" => school, "qualification" => text(qualification, 100), "field_of_study" => text(field_of_study, 100),
        "start_year" => year(start_year), "end_year" => year(end_year) }
    end

    def certification(name:, issuer: nil, issued_on: nil, expires_on: nil, credential_url: nil)
      name = text(name, 150)
      return nil unless name

      { "name" => name, "issuer" => text(issuer, 120), "issued_on" => issued_on&.iso8601,
        "expires_on" => expires_on&.iso8601, "credential_url" => https(credential_url) }
    end

    def language(name:, proficiency: nil)
      name = text(name, 60)
      name && { "name" => name, "proficiency" => UserLanguage.proficiency_from(proficiency).to_s }
    end

    def skills(list)
      Array(list).filter_map { |s| text(s, 40) }.uniq(&:downcase).first(LIMITS[:skills])
    end

    def draft(headline:, summary:, industry:, location:, positions:, educations:, skills:, certifications:, languages:)
      Draft.new(
        headline: text(headline, 120), summary: paragraph(summary, 500), industry: text(industry, 80),
        location: text(location, 100),
        positions: positions.compact.uniq { |p| [ p["title"].downcase, p["organization"].downcase ] }.first(LIMITS[:positions]),
        educations: educations.compact.uniq { |e| e["school"].downcase }.first(LIMITS[:educations]),
        skills: skills(skills),
        certifications: certifications.compact.uniq { |c| c["name"].downcase }.first(LIMITS[:certifications]),
        languages: languages.compact.uniq { |l| l["name"].downcase }.first(LIMITS[:languages])
      )
    end
  end

  # ── The data export ZIP ──────────────────────────────────────────
  class ExportReader
    FILES = %w[profile positions education skills certifications languages volunteering].freeze

    def initialize(path)
      @path = path
    end

    def call
      tables = read_tables
      raise Error, "That ZIP doesn't look like a LinkedIn data export (no Profile or Positions file)." if tables.empty?

      profile = tables["profile"]&.first || {}
      positions = rows(tables, "positions").map do |r|
        start_on = Clean.month(r["Started On"])
        end_on = Clean.month(r["Finished On"])
        Clean.position(title: r["Title"], organization: r["Company Name"], location: r["Location"],
                       description: r["Description"], start_on: start_on, end_on: end_on, current: r["Finished On"].blank?)
      end
      positions += rows(tables, "volunteering").map do |r|
        Clean.position(title: r["Role"], organization: r["Company Name"] || r["Organization"], description: r["Description"],
                       start_on: Clean.month(r["Started On"]), end_on: Clean.month(r["Finished On"]),
                       current: r["Finished On"].blank?, employment_type: "Volunteer")
      end
      educations = rows(tables, "education").map do |r|
        degree, field = r["Degree Name"].to_s.split(",", 2)
        Clean.education(school: r["School Name"], qualification: degree, field_of_study: field,
                        start_year: r["Start Date"], end_year: r["End Date"])
      end
      certifications = rows(tables, "certifications").map do |r|
        Clean.certification(name: r["Name"], issuer: r["Authority"], issued_on: Clean.month(r["Started On"]),
                            expires_on: Clean.month(r["Finished On"]), credential_url: r["Url"])
      end
      languages = rows(tables, "languages").map { |r| Clean.language(name: r["Name"], proficiency: r["Proficiency"]) }

      Clean.draft(headline: profile["Headline"], summary: profile["Summary"], industry: profile["Industry"],
                  location: profile["Geo Location"], positions: positions, educations: educations,
                  skills: rows(tables, "skills").map { |r| r["Name"] }, certifications: certifications, languages: languages)
    end

    private

    def rows(tables, name) = tables[name] || []

    # Only the CSVs we need, each size-checked before it's read.
    def read_tables
      tables = {}
      Zip::File.open(@path) do |zip|
        zip.each do |entry|
          next unless entry.file?

          key = File.basename(entry.name, ".*").downcase.gsub(/[^a-z]/, "")
          key = "volunteering" if key.start_with?("volunteer")
          next unless FILES.include?(key) && File.extname(entry.name).casecmp?(".csv")
          next if entry.size > MAX_CSV_ENTRY

          tables[key] = parse_csv(entry.get_input_stream.read(MAX_CSV_ENTRY).to_s)
        end
      end
      tables
    rescue Zip::Error => e
      raise Error, "We couldn't open that ZIP (#{e.message.first(80)})."
    end

    # Some LinkedIn CSVs start with a few "Notes:" lines before the header.
    def parse_csv(raw)
      text = raw.force_encoding("UTF-8").scrub("").delete_prefix("﻿")
      lines = text.lines
      start = lines.index { |l| l.count(",").positive? && !l.start_with?("Notes") } || 0
      CSV.parse(lines[start..].join, headers: true, liberal_parsing: true).map(&:to_h)
    rescue CSV::MalformedCSVError
      []
    end
  end

  # ── The profile PDF ──────────────────────────────────────────────
  class PdfReader
    SYSTEM_PROMPT = <<~PROMPT.freeze
      You turn the text of a LinkedIn profile PDF ("Save to PDF") into JSON.
      Use ONLY what the text says. Never invent or guess roles, dates, schools or skills.
      Reply with minified JSON and nothing else, with exactly these keys:
      {"headline":"","summary":"","industry":"","location":"",
       "positions":[{"title":"","company":"","location":"","start":"YYYY-MM","end":"YYYY-MM or null","current":true,"description":""}],
       "education":[{"school":"","degree":"","field":"","start_year":2012,"end_year":2016}],
       "skills":[""],
       "certifications":[{"name":"","issuer":"","issued":"YYYY-MM or null"}],
       "languages":[{"name":"","proficiency":"Native or Bilingual / Full Professional / Professional Working / Limited Working / Elementary"}]}
      Rules:
      - A company can list several roles; make one position per role, each with the company name.
      - "Present" means current: true and end null. A year with no month becomes YYYY-01.
      - "Top Skills" and any skills list go in skills. Leave a key empty ("" or []) when the text doesn't have it.
      - Ignore page numbers, "Page 1 of 3", contact links and the "Contact" block.
    PROMPT

    def initialize(path)
      @path = path
    end

    def call
      text = extract_text
      raise Error, "We couldn't read any text in that PDF. Try LinkedIn's “Save to PDF” again, or use the data export." if text.length < 40
      raise Error, "Reading PDFs isn't switched on here yet. Please use the LinkedIn data export ZIP instead." if Ai::Moderation::Client.stub?

      data = parse(ask_ai(text))
      build(data)
    end

    # LinkedIn's PDF has a sidebar (Contact, Top Skills, Languages,
    # Certifications) beside the main column, and the text comes out with both
    # on the same lines. Find where the right column starts and read the
    # columns one after the other.
    def self.unmix_columns(text)
      lines = text.to_s.lines.map(&:rstrip)
      width = lines.map(&:length).max.to_i
      return text.to_s if width < 40

      starts = lines.flat_map do |line|
        line.to_enum(:scan, /(?:\A {8,}| {3,})(?=\S)/).map { Regexp.last_match.end(0) }
      end
      column, hits = starts.select { |pos| pos.between?(width * 0.2, width * 0.75) }.tally.max_by(&:last)
      return text.to_s unless column && hits >= 3

      # Cut each line at the gap nearest that column, so a line that's a
      # character off doesn't lose a letter.
      cut = lines.map do |line|
        gap = line.to_enum(:scan, / {2,}(?=\S)/).map { Regexp.last_match.end(0) }.min_by { |pos| (pos - column).abs }
        gap && (gap - column).abs <= 6 ? gap : [ column, line.length ].min
      end
      left = lines.each_with_index.map { |line, i| line[0...cut[i]].to_s.strip }
      right = lines.each_with_index.map { |line, i| line[cut[i]..].to_s.strip }
      (left + [ "" ] + right).join("\n")
    end

    private

    def extract_text
      reader = PDF::Reader.new(@path)
      pages = reader.pages.first(MAX_PDF_PAGES).map { |page| self.class.unmix_columns(page.text) }
      pages.join("\n").gsub(/[ \t]+/, " ").gsub(/\n{3,}/, "\n\n").first(MAX_PDF_TEXT)
    rescue PDF::Reader::MalformedPDFError, PDF::Reader::UnsupportedFeatureError, PDF::Reader::EncryptedPDFError => e
      raise Error, "We couldn't open that PDF (#{e.class.name.demodulize})."
    end

    # Network seam — tests replace this.
    def ask_ai(text)
      Ai::Moderation::Client.call(system: SYSTEM_PROMPT, user: "LinkedIn profile text:\n\n#{text}")
    rescue Ai::Moderation::Client::Error, Timeout::Error, SocketError => e
      Rails.logger.warn("[LinkedinImport] AI: #{e.class}: #{e.message}")
      raise Error, "Reading the PDF didn't work just now. Please try again in a minute, or use the data export ZIP."
    end

    def parse(raw)
      text = raw.is_a?(Hash) ? Array(raw["content"]).find { |c| c["type"] == "text" }&.dig("text").to_s : raw.to_s
      text = text.sub(/\A```(?:json)?\s*/i, "").sub(/```\s*\z/, "").strip
      JSON.parse(text)
    rescue JSON::ParserError
      raise Error, "Reading the PDF didn't work just now. Please try again, or use the data export ZIP."
    end

    def build(data)
      list = ->(key) { Array(data[key]).select { |item| item.is_a?(Hash) } }
      Clean.draft(
        headline: data["headline"], summary: data["summary"], industry: data["industry"], location: data["location"],
        positions: list.call("positions").map do |p|
          Clean.position(title: p["title"], organization: p["company"], location: p["location"], description: p["description"],
                         start_on: Clean.month(p["start"]), end_on: Clean.month(p["end"]), current: p["current"] == true)
        end,
        educations: list.call("education").map do |e|
          Clean.education(school: e["school"], qualification: e["degree"], field_of_study: e["field"],
                          start_year: e["start_year"], end_year: e["end_year"])
        end,
        skills: Array(data["skills"]).grep(String),
        certifications: list.call("certifications").map { |c| Clean.certification(name: c["name"], issuer: c["issuer"], issued_on: Clean.month(c["issued"])) },
        languages: list.call("languages").map { |l| Clean.language(name: l["name"], proficiency: l["proficiency"]) }
      )
    end
  end
end

# frozen_string_literal: true

module LinkedinImport
  # Reads the text of LinkedIn's "Save to PDF" by its layout, without AI.
  # Used when the AI is switched off, slow or gives a bad answer.
  #
  # The PDF (after PdfReader.unmix_columns) has a sidebar block (Contact, Top
  # Skills, Languages, Certifications, Honors-Awards…) and a main block:
  # name, headline, location, Summary, Experience, Education. Experience lists
  # each company, optionally its total time ("4 years 2 months"), then each
  # role as: title, "Month YYYY - Present (x years)", location, description.
  #
  # Returns the same Hash shape the AI is asked for (see PdfReader::SYSTEM_PROMPT).
  class PdfRules
    MONTHS = %w[January February March April May June July August September October November December].freeze
    MONTH = /(?:#{(MONTHS + MONTHS.map { |m| m[0, 3] }).join("|")})/
    DATE_RANGE = /\A(?:(#{MONTH})\s+)?(\d{4})\s*[-–]\s*(?:(Present)|(?:(#{MONTH})\s+)?(\d{4}))(?:\s*\(.*\))?\z/i
    DURATION = /\A(?:\d+\s+(?:years?|yrs?|months?|mos?)\s*)+\z/i
    YEARS_IN_BRACKETS = /\((\d{4})\s*[-–]\s*(\d{4}|present)?\)/i
    SIDEBAR = [ "Contact", "Top Skills", "Skills", "Languages", "Certifications", "Honors-Awards", "Publications", "Patents" ].freeze
    MAIN = [ "Summary", "Experience", "Education" ].freeze
    HEADINGS = (SIDEBAR + MAIN).freeze
    JUNK = /\A(?:Page \d+ of \d+|\(LinkedIn\)|.*linkedin\.com.*|.*@.*\..*|\+?\d[\d\s()-]{6,})\z/i

    def initialize(text)
      @lines = text.to_s.lines.map { |l| l.strip.gsub(/\s+/, " ") }.reject { |l| l.empty? || l.match?(JUNK) }
    end

    def call
      sections = split_sections
      {
        "headline" => header[1].to_s, "location" => header[2].to_s, "industry" => "",
        "summary" => Array(sections["Summary"]).join(" "),
        "positions" => positions(Array(sections["Experience"])),
        "education" => education(Array(sections["Education"])),
        "skills" => Array(sections["Top Skills"]) + Array(sections["Skills"]),
        "languages" => Array(sections["Languages"]).map { |l| language(l) },
        "certifications" => Array(sections["Certifications"]).map { |name| { "name" => name, "issuer" => "", "issued" => nil } }
      }
    end

    private

    # { "Experience" => [lines…], … } — each heading's lines up to the next heading.
    def split_sections
      out = {}
      current = nil
      @lines.each do |line|
        if HEADINGS.include?(line)
          current = line
          out[current] ||= []
        elsif current
          out[current] << line
        end
      end
      # The main column's name / headline / location sit at the end of the
      # sidebar's last section (the columns are read one after the other).
      main_start = @lines.index { |l| MAIN.include?(l) }
      if main_start
        tail = @lines[[ main_start - 3, 0 ].max...main_start]
        SIDEBAR.each { |h| out[h] -= tail if out[h] }
      end
      out
    end

    # [name, headline, location]: the three lines before Summary / Experience.
    def header
      @header ||= begin
        main_start = @lines.index { |l| MAIN.include?(l) }
        main_start ? @lines[[ main_start - 3, 0 ].max...main_start] : []
      end
    end

    def positions(lines)
      roles = []
      company = nil
      lines.each_with_index do |line, i|
        match = line.match(DATE_RANGE)
        next unless match && i >= 1

        title = lines[i - 1]
        before = i >= 2 ? lines[i - 2] : nil
        if before&.match?(DURATION)
          company = i >= 3 ? lines[i - 3] : nil
        elsif before && !(company && continues_previous_company?(roles, lines, before))
          company = before
        end
        location = lines[i + 1] if lines[i + 1] && location?(lines[i + 1])
        roles << { "title" => title, "company" => company.to_s, "location" => location.to_s,
                   "start" => month(match[1], match[2]), "end" => match[3] ? nil : month(match[4], match[5]),
                   "current" => match[3].present?, "description" => "", "_at" => i }
      end
      roles.each_with_index do |role, n|
        from = role["_at"] + (role["location"].present? ? 2 : 1)
        to = roles[n + 1] ? roles[n + 1]["_at"] - 2 : lines.length
        role["description"] = lines[from...to].to_a.reject { |l| l.match?(DURATION) }.join(" ").first(1_000)
      end
      roles.each { |r| r.delete("_at") }
    end

    # LinkedIn lists several titles under one employer: the next title then
    # follows the previous role's location or description, not a company name.
    def continues_previous_company?(roles, lines, before)
      prev = roles.last
      return false unless prev
      before == lines[prev["_at"] + 1] || sentence?(before)
    end

    def sentence?(line)
      line.end_with?(".", "!", "?") || line.length > 60
    end

    def education(lines)
      lines.each_with_index.filter_map do |line, i|
        years = line.match(YEARS_IN_BRACKETS)
        next unless years && i >= 1

        degree, field = line.sub(YEARS_IN_BRACKETS, "").sub(/\s*·\s*\z/, "").split(",", 2).map { |s| s.to_s.strip }
        { "school" => lines[i - 1], "degree" => degree.to_s, "field" => field.to_s,
          "start_year" => years[1].to_i, "end_year" => years[2].to_s.match?(/\d/) ? years[2].to_i : nil }
      end
    end

    def language(line)
      name, proficiency = line.match(/\A(.+?)\s*\((.+)\)\z/)&.captures || [ line, nil ]
      { "name" => name, "proficiency" => proficiency.to_s }
    end

    def location?(line)
      line.length <= 80 && !line.match?(DATE_RANGE) && (line.include?(",") || line.match?(/\b(Remote|Nigeria|Ghana|Kenya|Area|Metropolitan|State|United)\b/i))
    end

    def month(name, year)
      return nil if year.blank?
      number = name ? (MONTHS.index { |m| m.downcase.start_with?(name.downcase[0, 3]) }.to_i + 1) : 1
      format("%04d-%02d", year.to_i, number)
    end
  end
end

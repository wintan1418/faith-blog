# frozen_string_literal: true

# Reads a part marker out of a breath title, so "The Gospel and Material
# Prosperity (Part 2)" is seen as part 2 of "The Gospel and Material
# Prosperity". Used by the composer's "add this to your series?" hint and by
# `rake series:suggest`.
#
# Titles are compared after NFKC normalisation: many writers style titles in
# Unicode "mathematical bold" ("𝗪𝗵𝗼 𝗜𝘀 𝗮 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿? (𝟭)"), which NFKC folds
# to plain letters and digits. The author's title itself is never changed.
#
# Markers understood (case-insensitive), anywhere after some base text, with
# or without a subtitle after them:
#   "(1)", "(#1)", "(2/7)", "#1", "Part 2", "Pt. 2", "Part II", ", Part 3",
#   "Day 1.", "Episode 4" / "Ep 4"
#
# A marker with no words before it ("(2/7) The Friend That Offends") still
# gives a part number, but no base title to group by (key is nil).
class SeriesTitle
  ROMAN = { "i" => 1, "ii" => 2, "iii" => 3, "iv" => 4, "v" => 5, "vi" => 6, "vii" => 7,
            "viii" => 8, "ix" => 9, "x" => 10, "xi" => 11, "xii" => 12 }.freeze

  MARKER = /
    (?:
      \(\s*\#?\s*(?<num>\d{1,3})\s*(?:\/\s*\d{1,3}\s*)?\)                 # (1)  (#1)  (2 of 7, written with a slash)
      | \(\s*(?:part|pt\.?)\s*(?<num>\d{1,3}|[ivx]{1,4})\s*\)           # (Part 2)
      | (?<![\w])(?:part|pt\.?|day|episode|ep\.?)\s*(?<num>\d{1,3})(?!\d) # Part 2  Day 1  Ep 4
      | (?<![\w])part\s+(?<num>[ivx]{1,4})(?![\w])                       # Part II
      | \#\s*(?<num>\d{1,3})(?!\d)                                       # #3
    )
  /ix

  # Characters trimmed from the end of the base ("The Whole Man. Day 1" → "The Whole Man").
  BASE_TRAIL = /[\s,:;.\-–—|\/~]+\z/

  Parsed = Data.define(:base, :key, :part)

  # The title as plain text: bold/italic math letters, full-width digits and
  # the like folded to ASCII-ish text, whitespace squeezed.
  def self.normalize(title)
    title.to_s.unicode_normalize(:nfkc).squish
  rescue ArgumentError, Encoding::CompatibilityError
    title.to_s.squish
  end

  # The grouping key for a base title: case, punctuation and spacing don't count.
  def self.key_for(text)
    normalize(text).downcase.gsub(/[^\p{Alnum}]+/, " ").squish
  end

  # Parsed(base:, key:, part:) or nil when the title has no part marker.
  # base and key are nil when the marker has no real words before it.
  def self.parse(title)
    text = normalize(title)
    return if text.blank?

    leading = nil
    text.to_enum(:scan, MARKER).each do
      match = Regexp.last_match
      base = text[0...match.begin(0)].sub(BASE_TRAIL, "").strip
      key = key_for(base)
      part = part_number(match[:num])
      if key.length < 3
        leading ||= Parsed.new(base: nil, key: nil, part: part)
        next
      end

      return Parsed.new(base: base, key: key, part: part)
    end
    leading
  end

  # The title a breath goes by for series detection: its title, or for an
  # untitled breath the first line of its words when that reads like one
  # ("Faith vs Tradition (4)" on a line of its own).
  def self.effective_title(post)
    return post.title if post.title.present?

    first_line = post.content&.to_plain_text.to_s.strip.lines.first.to_s.squish
    first_line if first_line.present? && first_line.length <= 150
  end

  def self.part_number(raw)
    raw = raw.to_s.downcase
    raw.match?(/\A\d+\z/) ? raw.to_i : ROMAN[raw]
  end
end

# frozen_string_literal: true

module Celebrations
  # The built-in calendar: Christian feasts, family days and national days,
  # with their dates worked out for any year (Easter by the Gregorian
  # computus, US Thanksgiving on the 4th Thursday of November…).
  #
  #   Celebrations::Presets.seed!   # drafts for the next 12 months
  #
  # Presets are created as drafts for an admin to review and activate, unless
  # the admin turned on "auto-activate presets" (off by default). Each one has
  # a preset_key ("thanksgiving-us-2026"), so running it again never makes
  # duplicates, and an occasion the admin deleted is not brought back unless
  # asked (`restore: true`).
  class Presets
    Preset = Data.define(:key, :name, :greeting_title, :message, :scripture_reference, :scripture_text,
                         :hashtag, :accent_color, :emblem, :effect, :time_zone, :country_codes, :date, :days, :starts_hour)

    LAGOS = "Africa/Lagos"

    def self.seed!(from: Date.current, months: 12, activate: Celebration.auto_activate_presets?)
      upcoming(from: from, months: months).filter_map do |preset|
        next if Celebration.exists?(preset_key: preset.key)

        Celebration.create!(attributes_for(preset).merge(status: activate ? :live : :draft))
      rescue ActiveRecord::RecordNotUnique
        nil
      end
    end

    # Every preset whose occasion ends on or after `from` and starts within `months`.
    def self.upcoming(from: Date.current, months: 12)
      last = from.advance(months: months)
      (from.year..last.year).flat_map { |year| for_year(year) }
                            .select { |p| p.date + (p.days - 1) >= from && p.date < last }
                            .sort_by(&:date)
    end

    def self.attributes_for(preset)
      zone = ActiveSupport::TimeZone[preset.time_zone]
      starts = zone.local(preset.date.year, preset.date.month, preset.date.day, preset.starts_hour)
      ends = zone.local(preset.date.year, preset.date.month, preset.date.day).advance(days: preset.days)
      preset.to_h.except(:key, :date, :days, :starts_hour).merge(
        preset_key: preset.key, starts_at: starts, ends_at: ends,
        audience: preset.country_codes.any? ? :countries : :everyone
      )
    end

    # Western (Gregorian) Easter Sunday: the anonymous computus.
    def self.easter(year)
      a = year % 19
      b, c = year.divmod(100)
      d, e = b.divmod(4)
      f = (b + 8) / 25
      g = (b - f + 1) / 3
      h = (19 * a + b - d - g + 15) % 30
      i, k = c.divmod(4)
      l = (32 + 2 * e + 2 * i - h - k) % 7
      m = (a + 11 * h + 22 * l) / 451
      month, day = (h + l - 7 * m + 114).divmod(31)
      Date.new(year, month, day + 1)
    end

    # The nth `wday` (0 = Sunday … 6 = Saturday) of a month.
    def self.nth_weekday(year, month, wday, nth)
      first = Date.new(year, month, 1)
      first + ((wday - first.wday) % 7) + (nth - 1) * 7
    end

    def self.for_year(year)
      easter = easter(year)
      [
        build("new-year", year, Date.new(year, 1, 1), days: 1, name: "New Year",
              greeting_title: "Happy New Year", emblem: "✨", effect: "confetti", accent_color: "#0e5c43",
              message: "A new year, the same faithful God. Thank you for walking with us, brethren.",
              ref: "Lamentations 3:22-23", text: "It is of the LORD's mercies that we are not consumed, because his compassions fail not. They are new every morning: great is thy faithfulness.",
              hashtag: "HappyNewYear"),
        build("ghana-independence", year, Date.new(year, 3, 6), name: "Ghana Independence Day",
              greeting_title: "Happy Independence Day, Ghana", emblem: "🇬🇭", effect: "confetti", accent_color: "#006b3f",
              countries: %w[GH], zone: "Africa/Accra",
              message: "Freedom and justice. Praying for peace and prosperity across Ghana today.",
              ref: "Psalm 33:12", text: "Blessed is the nation whose God is the LORD; and the people whom he hath chosen for his own inheritance.",
              hashtag: "GhanaAt#{year - 1957}"),
        build("mothering-sunday", year, easter - 21, name: "Mothering Sunday",
              greeting_title: "Happy Mothering Sunday", emblem: "💐", effect: "petals", accent_color: "#9d4b73",
              countries: %w[GB NG IE], zone: "Europe/London",
              message: "Honouring the mothers and mother-figures who carried us in prayer.",
              ref: "Proverbs 31:28", text: "Her children arise up, and call her blessed; her husband also, and he praiseth her.",
              hashtag: "MotheringSunday"),
        build("good-friday", year, easter - 2, name: "Good Friday",
              greeting_title: "Good Friday", emblem: "✝️", effect: "none", accent_color: "#57534e",
              message: "Today we remember the cross, and the love that held Him there.",
              ref: "Isaiah 53:5", text: "But he was wounded for our transgressions, he was bruised for our iniquities: the chastisement of our peace was upon him; and with his stripes we are healed.",
              hashtag: "GoodFriday"),
        build("easter", year, easter, days: 2, name: "Easter",
              greeting_title: "He is risen", emblem: "🌿", effect: "petals", accent_color: "#b87a14",
              message: "The tomb is empty and our hope is alive. Happy Easter, brethren!",
              ref: "Matthew 28:6", text: "He is not here: for he is risen, as he said. Come, see the place where the Lord lay.",
              hashtag: "HeIsRisen"),
        build("freedom-day-za", year, Date.new(year, 4, 27), name: "Freedom Day (South Africa)",
              greeting_title: "Happy Freedom Day, South Africa", emblem: "🇿🇦", effect: "confetti", accent_color: "#007749",
              countries: %w[ZA], zone: "Africa/Johannesburg",
              message: "Giving thanks for freedom, and praying for unity across the rainbow nation.",
              ref: "Galatians 5:1", text: "Stand fast therefore in the liberty wherewith Christ hath made us free, and be not entangled again with the yoke of bondage.",
              hashtag: "FreedomDay"),
        build("mothers-day", year, nth_weekday(year, 5, 0, 2), name: "Mother's Day",
              greeting_title: "Happy Mother's Day", emblem: "💐", effect: "petals", accent_color: "#9d4b73",
              countries: %w[US CA GH KE ZA AU UG], zone: "America/New_York",
              message: "Honouring the mothers and mother-figures who carried us in prayer.",
              ref: "Proverbs 31:28", text: "Her children arise up, and call her blessed; her husband also, and he praiseth her.",
              hashtag: "MothersDay"),
        build("pentecost", year, easter + 49, name: "Pentecost Sunday",
              greeting_title: "Happy Pentecost", emblem: "🔥", effect: "lights", accent_color: "#c2410c",
              message: "Celebrating the gift of the Holy Spirit, who still fills and sends His people.",
              ref: "Acts 2:4", text: "And they were all filled with the Holy Ghost, and began to speak with other tongues, as the Spirit gave them utterance.",
              hashtag: "Pentecost"),
        build("fathers-day", year, nth_weekday(year, 6, 0, 3), name: "Father's Day",
              greeting_title: "Happy Father's Day", emblem: "🤍", effect: "stars", accent_color: "#1e4e79",
              countries: %w[US GB NG GH KE ZA CA IE UG], zone: LAGOS,
              message: "Thanking God for fathers and father-figures who lead with love.",
              ref: "Psalm 103:13", text: "Like as a father pitieth his children, so the LORD pitieth them that fear him.",
              hashtag: "FathersDay"),
        build("independence-day-us", year, Date.new(year, 7, 4), name: "Independence Day (US)",
              greeting_title: "Happy Fourth of July", emblem: "🇺🇸", effect: "stars", accent_color: "#1e3a8a",
              countries: %w[US], zone: "America/New_York",
              message: "Grateful for freedom, and praying for our neighbours across America.",
              ref: "Galatians 5:1", text: "Stand fast therefore in the liberty wherewith Christ hath made us free, and be not entangled again with the yoke of bondage.",
              hashtag: "FourthOfJuly"),
        build("nigeria-independence", year, Date.new(year, 10, 1), name: "Nigeria Independence Day",
              greeting_title: "Happy Independence Day, Nigeria", emblem: "🇳🇬", effect: "confetti", accent_color: "#008751",
              countries: %w[NG], zone: LAGOS,
              message: "Thanking God for Nigeria, and praying for peace, justice and good leaders.",
              ref: "Psalm 33:12", text: "Blessed is the nation whose God is the LORD; and the people whom he hath chosen for his own inheritance.",
              hashtag: "NigeriaAt#{year - 1960}"),
        build("thanksgiving-ca", year, nth_weekday(year, 10, 1, 2), name: "Thanksgiving (Canada)",
              greeting_title: "Happy Thanksgiving", emblem: "🍁", effect: "leaves", accent_color: "#b45309",
              countries: %w[CA], zone: "America/Toronto",
              message: "Counting our blessings together today. Grateful for every one of you.",
              ref: "1 Thessalonians 5:18", text: "In every thing give thanks: for this is the will of God in Christ Jesus concerning you.",
              hashtag: "Thanksgiving"),
        build("thanksgiving-us", year, nth_weekday(year, 11, 4, 4), name: "Thanksgiving (US)",
              greeting_title: "Happy Thanksgiving", emblem: "🍂", effect: "leaves", accent_color: "#b45309",
              countries: %w[US], zone: "America/New_York",
              message: "Counting our blessings together today. Grateful for every one of you.",
              ref: "Psalm 100:4", text: "Enter into his gates with thanksgiving, and into his courts with praise: be thankful unto him, and bless his name.",
              hashtag: "Thanksgiving"),
        build("jamhuri-day", year, Date.new(year, 12, 12), name: "Jamhuri Day (Kenya)",
              greeting_title: "Happy Jamhuri Day, Kenya", emblem: "🇰🇪", effect: "confetti", accent_color: "#006600",
              countries: %w[KE], zone: "Africa/Nairobi",
              message: "Celebrating Kenya today, and praying for peace and blessing on every home.",
              ref: "Psalm 33:12", text: "Blessed is the nation whose God is the LORD; and the people whom he hath chosen for his own inheritance.",
              hashtag: "JamhuriDay"),
        build("christmas", year, Date.new(year, 12, 24), days: 3, starts_hour: 18, name: "Christmas",
              greeting_title: "Merry Christmas", emblem: "⭐", effect: "lights", accent_color: "#9f1d2b",
              message: "Unto us a Saviour is born. Wishing you and yours a joyful, peaceful Christmas.",
              ref: "Luke 2:11", text: "For unto you is born this day in the city of David a Saviour, which is Christ the Lord.",
              hashtag: "MerryChristmas")
      ]
    end

    def self.build(slug, year, date, name:, greeting_title:, message:, ref:, text:, hashtag:, accent_color:, emblem:, effect:,
                   days: 1, starts_hour: 0, countries: [], zone: LAGOS)
      Preset.new(key: "#{slug}-#{year}", name: "#{name} #{year}", greeting_title: greeting_title, message: message,
                 scripture_reference: ref, scripture_text: text, hashtag: hashtag, accent_color: accent_color,
                 emblem: emblem, effect: effect, time_zone: zone, country_codes: countries, date: date,
                 days: days, starts_hour: starts_hour)
    end
    private_class_method :build
  end
end

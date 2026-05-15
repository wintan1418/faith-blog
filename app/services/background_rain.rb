# frozen_string_literal: true

# Curated pool of ambient "rain" lines for the page background — short
# scripture fragments on the four themes the user asked for (salvation,
# faith, the throne, eternal life), a handful of brethren-life lines,
# and a random sample of active Golden Breaths from the system. Returned
# as a shuffled, capped list so the controller can pick from it at random.
class BackgroundRain
  CAP = 28

  SCRIPTURES = [
    # Salvation
    { text: "For God so loved the world, that he gave his only begotten Son.", cite: "John 3:16" },
    { text: "Believe on the Lord Jesus Christ, and thou shalt be saved.",      cite: "Acts 16:31" },
    { text: "Whosoever shall call upon the name of the Lord shall be saved.",  cite: "Romans 10:13" },
    { text: "By grace are ye saved through faith.",                            cite: "Ephesians 2:8" },
    { text: "Neither is there salvation in any other.",                        cite: "Acts 4:12" },
    # Faith
    { text: "Now faith is the substance of things hoped for.",                 cite: "Hebrews 11:1" },
    { text: "Without faith it is impossible to please Him.",                   cite: "Hebrews 11:6" },
    { text: "The just shall live by faith.",                                   cite: "Romans 1:17" },
    { text: "Faith cometh by hearing, and hearing by the word of God.",        cite: "Romans 10:17" },
    { text: "We walk by faith, not by sight.",                                 cite: "2 Corinthians 5:7" },
    # The throne
    { text: "Let us therefore come boldly unto the throne of grace.",          cite: "Hebrews 4:16" },
    { text: "A throne was set in heaven, and One sat on the throne.",          cite: "Revelation 4:2" },
    { text: "The Lord hath prepared His throne in the heavens.",               cite: "Psalm 103:19" },
    { text: "He shall sit upon the throne of His glory.",                      cite: "Matthew 25:31" },
    # Eternal life
    { text: "He that believeth on the Son hath everlasting life.",             cite: "John 3:36" },
    { text: "I give unto them eternal life; and they shall never perish.",     cite: "John 10:28" },
    { text: "The gift of God is eternal life through Jesus Christ.",           cite: "Romans 6:23" },
    { text: "This is life eternal, that they might know Thee.",                cite: "John 17:3" }
  ].freeze

  BRETHREN = [
    "Breathe — He carries you.",
    "Brother, sister — you are seen, you are loved.",
    "We are family in Christ Jesus.",
    "One breath, one heart, one Lord.",
    "Carry each other's burdens.",
    "Pray for one another, and be healed.",
    "Walk softly. Speak kindly. Hope deeply."
  ].freeze

  def self.items(limit: CAP)
    pool = []
    pool += SCRIPTURES.map { |s| { kind: "scripture", text: s[:text], cite: s[:cite] } }
    pool += BRETHREN.map   { |t| { kind: "brethren",  text: t } }

    if defined?(GoldenBreath)
      goldens = GoldenBreath.active.order(Arel.sql("RANDOM()")).limit(8) rescue []
      goldens.each do |g|
        text = g.text.to_s.strip
        next if text.blank?
        pool << { kind: "golden", text: text.length > 140 ? "#{text[0, 140].rstrip}…" : text,
                  cite: g.author_name.presence }
      end
    end

    pool.shuffle.first(limit)
  end
end

# frozen_string_literal: true

# Instant, local check for offensive words in messages, comments, posts and
# usernames. It runs before anything is saved (no network, never "fails open"),
# and the AI moderators still review posts and comments afterwards.
#
# It sees through common disguises: f*ck, sh1t, fuuuck, f u c k, $hit, b!tch.
#
# Deliberately NOT blocked, because they are Bible words people quote:
#   hell, damn, ass, whore, harlot, bastard, piss, cock (the cock crowed), dung.
# Also not blocked: words used in honest testimony (porn, addiction, drunk…).
module CleanLanguage
  MESSAGE = "Please keep it kind: this has language that isn't allowed on Brethreign. Edit it and try again."

  # Blocked if the word appears anywhere inside a token (motherf***er, bulls**t).
  ANYWHERE = %w[fuck fck shit cunt].freeze

  # Blocked when a token starts with these (bitches, sluttish, retarded…).
  STARTS_WITH = %w[
    bitch biatch slut twat wanker wank pussy dildo blowjob handjob cumshot
    nigger nigga faggot fagot retard motherf
  ].freeze

  # Blocked only as whole words.
  WHOLE_WORDS = %w[
    fag fags bollocks bollock jizz cum cums cumming tits titties boob boobs
    nude nudes horny
    ashawo oloshi werey mumu olodo
  ].freeze

  # Innocent words that happen to contain a blocked one.
  ALLOWED = %w[shiitake shitake scunthorpe niger].freeze
  ALLOWED_PREFIXES = %w[nigeri].freeze # Nigeria, Nigerian, Nigerians
  # Bible names and words that contain a blocked word (found by scanning the whole KJV):
  # shittim wood, Shittah, Abel-shittim, Beth-shittah, Girgashites, Mushites, Elkoshite, Shitrai.
  ALLOWED_PARTS = %w[shittim shittah girgash mushite elkoshite shitrai].freeze

  LEET = { "0" => "o", "1" => "i", "!" => "i", "|" => "i", "3" => "e", "4" => "a", "@" => "a",
           "5" => "s", "$" => "s", "7" => "t", "+" => "t", "8" => "b", "9" => "g" }.freeze

  module_function

  def offensive?(text) = offending_word(text).present?

  # The first offending (normalised) word, for logs and tests.
  def offending_word(text)
    candidates(text.to_s).each do |raw, word|
      next if ALLOWED.include?(word) || ALLOWED_PREFIXES.any? { |ok| word.start_with?(ok) }
      next if ALLOWED_PARTS.any? { |ok| word.include?(ok) }

      collapsed = word.squeeze
      return raw if ANYWHERE.any? { |bad| word.include?(bad) || collapsed.include?(bad.squeeze) }
      return raw if STARTS_WITH.any? { |bad| word.start_with?(bad) || collapsed.start_with?(bad.squeeze) }
      return raw if WHOLE_WORDS.include?(word) || WHOLE_WORDS.include?(collapsed)
    end
    nil
  end

  # Each word, normalised (lowercase, leet-speak undone, punctuation inside removed),
  # plus runs of single letters joined up ("f u c k" → "fuck").
  def candidates(text)
    tokens = text.downcase.unicode_normalize(:nfkd).split(/\s+/).compact_blank
    words = tokens.map { |t| [ t, normalise(t) ] }
    singles = tokens.chunk_while { |a, b| normalise(a).size == 1 && normalise(b).size == 1 }
                    .select { |run| run.size >= 3 && run.all? { |t| normalise(t).size == 1 } }
                    .map { |run| [ run.join(" "), run.map { |t| normalise(t) }.join ] }
    words + singles
  end

  def normalise(token)
    token.chars.map { |c| LEET.fetch(c, c) }.join.gsub(/[^a-z]/, "")
  end
end

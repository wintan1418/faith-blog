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

  # Insults are blocked when aimed at someone ("you idiot", "you're stupid",
  # "stupid man"), not as bare words: the Bible says "the fool hath said",
  # people say "I was a fool before Christ", and "you are mad blessed" is praise.
  INSULTS = %w[
    idiot idiots stupid stupidity moron morons imbecile dumb dummy fool fools foolish
    madman madmen madwoman useless worthless nonsense rubbish senseless brainless
    mumu olodo werey mugu ewu bastard bastards loser losers dullard
  ].freeze
  # Only an insult with nothing praising after it: "you are mad" yes, "you are mad blessed" no.
  SOFT_INSULTS = %w[mad crazy silly ugly dog pig goat animal witch].freeze # not "devil": "one of you is a devil" (John 6:70)
  INSULT_PEOPLE = %w[man men woman women boy boys girl girls guy guys person people thing things fellow].freeze

  YOU = /(?:you|u|ya|yu)/
  YOU_ARE = /(?:#{YOU}\s+(?:are|r|re|is)|youre|ur|ure)/
  FILLER = /(?:\s+(?:a|an|such|so|very|really|just|this|one|big|total|complete|ode))*/
  INSULT_WORDS = /(?:#{INSULTS.join("|")})/
  SOFT_WORDS = /(?:#{SOFT_INSULTS.join("|")})/
  PEOPLE_WORDS = /(?:#{INSULT_PEOPLE.join("|")})/
  # Harsh adjectives that insult when put in front of a person ("stupid man").
  # Not "foolish"/"mad": the Bible says "O foolish people" and "mad men".
  HARSH = /(?:stupid|useless|worthless|senseless|brainless|idiotic|rubbish|nonsense)/ # not "dumb": KJV "a dumb man" = unable to speak
  DIRECTED = [
    /\b(?:#{YOU_ARE}|#{YOU})#{FILLER}\s+#{INSULT_WORDS}\b/,                      # you idiot / you're a stupid
    /\b(?:#{YOU_ARE}|#{YOU})#{FILLER}\s+#{SOFT_WORDS}(?:\s+#{PEOPLE_WORDS})?\s*$/, # you are mad (end of sentence)
    /\b#{HARSH}\s+#{PEOPLE_WORDS}\b/,                                             # stupid man, useless girl
    # "Shut up!" said to someone: at the start or end of a sentence, not "shut up the heaven".
    /(?:\A\s*(?:just\s+|you\s+)?shut\s+up(?:\s+(?:you|man|joor|jare))?\s*\z|\bshut\s+your\s+(?:mouth|trap)\b)/
].freeze

  module_function

  def offensive?(text) = offending_word(text).present? || insulting?(text)

  # A directed insult, judged sentence by sentence on cleaned-up words.
  def insulting?(text)
    text.to_s.downcase.split(/[.!?;\n]+/).any? do |sentence|
      words = sentence.split(/\s+/).map { |t| normalise(t) }.compact_blank.join(" ")
      DIRECTED.any? { |pattern| words.match?(pattern) }
    end
  end

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

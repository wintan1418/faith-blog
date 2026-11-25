# frozen_string_literal: true

# Page handles (/p/<handle>, @handle): what's reserved, what's protected, and
# a tidy website address.
#
# * RESERVED: words the site uses or that would mislead (admin, support,
#   official…). Nobody can take them; staff can, through the official task.
# * PROTECTED: well-known churches, denominations and bodies. A member can't
#   take these handles (so nobody squats "@rccg"), and a page whose *name*
#   matches is flagged for admins to check before it is ever verified.
# * A handle can't be a member's username either, so @handle always means one
#   thing.
module PageHandle
  RESERVED = %w[
    brethreign brethren official admin admins administrator support help helpdesk staff team moderator moderators
    mod mods security safety trust abuse report reports legal privacy terms about contact press media_kit
    api app apps www mail email root system null undefined everyone all here me you page pages p new edit manage
    settings feed search explore discover home login logout signin signup register join invite verify verified
    billing pro premium payments give giving donate store shop jobs careers blog news rooms circles series bible
    scripture prayer prayers notifications inbox messages
  ].freeze

  PROTECTED = %w[
    rccg redeemedchristian winners livingfaith deeperlife mfm mountainoffire cac christapostolic ecwa
    anglican churchofengland catholic vatican pope methodist baptist presbyterian lutheran pentecostal
    assembliesofgod cherubimandseraphim celestial foursquare coza dunamis daystar salvationarmy hillsong elevation
    bethel lakewood churchofgod adventist seventhday orthodox coptic worldvision compassion samaritanspurse
    redcross unicef youversion biblesociety gideons scriptureunion fcs nifes ccc wcc
  ].freeze

  module_function

  def key(text) = text.to_s.downcase.gsub(/[^a-z0-9]/, "")

  def reserved?(handle) = RESERVED.include?(handle.to_s.downcase)

  def protected_handle?(handle)
    k = key(handle)
    tokens = handle.to_s.downcase.split(/[^a-z]+/)
    PROTECTED.any? do |word|
      k == word || tokens.include?(word) || k.start_with?(word) || (word.length >= 5 && k.include?(word))
    end
  end

  # "Redeemed Christian Church of God, Akure" → true.
  def protected_name?(name)
    k = key(name)
    PROTECTED.any? { |word| word.length >= 5 && k.include?(word) } ||
      %w[rccg mfm cac ecwa coza].any? { |abbr| name.to_s.downcase.split(/[^a-z0-9]+/).include?(abbr) }
  end

  # Why a member can't have this handle, or nil.
  def problem_with(handle)
    return "is reserved" if reserved?(handle)
    return "belongs to a well-known church or organisation. Pick another; if you run it, ask us to verify you" if protected_handle?(handle)
    return "is someone's username" if User.where("lower(username) = ?", handle.to_s.downcase).exists?

    nil
  end

  # A handle suggestion from a name: "Grace Chapel Akure" → "gracechapelakure".
  def suggest(name)
    base = name.to_s.unicode_normalize(:nfkd).gsub(/[^\x00-\x7F]/, "").downcase.gsub(/[^a-z0-9]+/, "")[0, 26]
    base = "page#{base}" if base.length < 3
    return base unless taken?(base)

    (2..99).each do |n|
      candidate = "#{base[0, 27]}#{n}"
      return candidate unless taken?(candidate)
    end
    "#{base[0, 22]}#{SecureRandom.hex(3)}"
  end

  def taken?(handle)
    problem_with(handle).present? || Page.by_handle(handle).exists?
  end

  # "gracechapel.org" → "https://gracechapel.org".
  def normalize_url(value)
    url = value.to_s.strip
    return nil if url.blank?

    url.match?(%r{\Ahttps?://}i) ? url : "https://#{url}"
  end
end

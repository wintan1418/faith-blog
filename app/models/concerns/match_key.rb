# frozen_string_literal: true

# Turns free text into a comparable key, so "R.C.C.G  Jubilee Parish", "rccg jubilee parish"
# and "RCCG Jubilee Parish," all match. Used for assembly, city, organisation and job title.
module MatchKey
  def self.for(text)
    key = text.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
               .downcase.delete(".'’").gsub(/[^a-z0-9]+/, " ").squish
    key.presence
  end

  # "Lagos, Nigeria" → "lagos" (the city part of a location).
  def self.city(location)
    self.for(location.to_s.split(",").first)
  end
end

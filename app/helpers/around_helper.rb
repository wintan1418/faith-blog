# frozen_string_literal: true

# "Breathers around you" and where members live.
module AroundHelper
  COUNTRY_SHORT = { "US" => "USA", "GB" => "UK", "AE" => "UAE", "CD" => "DR Congo" }.freeze

  CITY_VISIBILITY_CHOICES = [
    [ "everyone", "Everyone on Brethreign" ],
    [ "connections", "Only my connections" ],
    [ "only_me", "Only me" ]
  ].freeze

  # The member's location text, if this viewer may see it (their city visibility).
  def visible_location(profile)
    return unless profile&.location.present?

    viewer = current_user if user_signed_in?
    profile.location if profile.city_visible_to?(viewer)
  end

  # "Houston, Texas · United States"
  def around_city_line(city)
    [ [ city.name, city.region ].compact.join(", "), city.country_name ].join(" · ")
  end

  def around_country_short(city) = COUNTRY_SHORT.fetch(city.country_code, city.country_name)

  # The country to favour in the city picker (Cloudflare's guess from the IP).
  def city_picker_country_hint
    request.headers["CF-IPCountry"].to_s.upcase[/\A[A-Z]{2}\z/]
  end

  # The chip that says how far: "Same city", "Owo · ~40 km", "Lagos · Same country".
  def around_distance_chip(person)
    return "Same city" if person.bucket == :same_city

    "#{person.city&.name} · #{person.distance_label}"
  end

  # Three ways to start, for the Say hello sheet.
  def around_hello_lines(person, my_city, rooms)
    first = person.user.display_name
    where = person.city&.name
    opener = person.bucket == :same_city ? "Hi #{first}! I saw you're in #{where} too." : "Hi #{first}! I saw you're close by in #{where}."
    third = if (industry = person.user.profile&.industry.presence) && industry == current_user.profile&.industry
              "Hi! We're both in #{industry}. Fancy a chat sometime?"
    elsif visible_open_to(person.user).include?("mentoring")
              "Hi! I saw you're open to mentoring. Could I ask you a few questions sometime?"
    elsif rooms.present?
              "Hi! We're both in #{rooms.first}. Great to find you nearby."
    else
              "Hi! Great to find a brother or sister nearby. How long have you been in #{where}?"
    end
    [ "#{opener} Would love to connect.", "Hello! Do you know a good fellowship around #{my_city.name}?", third ]
  end
end

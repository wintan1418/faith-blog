# frozen_string_literal: true

# A short, human description of the device and rough place a request came
# from: "Chrome on Windows", "Brethreign app on iPhone", "Lagos, Nigeria".
# The place comes only from Cloudflare's visitor headers (city when Cloudflare
# sends it, else the country); no IP lookup service is called.
DeviceInfo = Data.define(:name, :platform, :user_agent, :ip, :location) do
  def self.from(request)
    ua = request.user_agent.to_s.first(500)
    new(name: name_for(ua), platform: platform_for(ua), user_agent: ua,
        ip: request.remote_ip, location: location_for(request))
  end

  def self.platform_for(ua)
    return "web" unless ua.include?("Hotwire Native")

    ua.include?("Android") ? "android_app" : "ios_app"
  end

  def self.name_for(ua)
    return "Unknown device" if ua.blank?

    os = os_for(ua)
    if ua.include?("Hotwire Native")
      return "Brethreign app on #{ua.include?('Android') ? 'Android' : (ua.include?('iPad') ? 'iPad' : 'iPhone')}"
    end

    browser = browser_for(ua)
    [ browser, os ].compact.join(" on ").presence || "Unknown device"
  end

  def self.browser_for(ua)
    case ua
    when /Edg(e|A|iOS)?\// then "Edge"
    when /OPR\/|Opera/ then "Opera"
    when /SamsungBrowser/ then "Samsung Internet"
    when /CriOS|Chrome\// then "Chrome"
    when /FxiOS|Firefox\// then "Firefox"
    when /Safari\// then "Safari"
    else "A browser"
    end
  end

  def self.os_for(ua)
    case ua
    when /iPhone/ then "iPhone"
    when /iPad/ then "iPad"
    when /Android/ then "Android"
    when /Windows/ then "Windows"
    when /CrOS/ then "ChromeOS"
    when /Mac OS X|Macintosh/ then "Mac"
    when /Linux/ then "Linux"
    end
  end

  def self.location_for(request)
    country_code = request.headers["CF-IPCountry"].to_s.upcase[/\A[A-Z]{2}\z/]
    country_code = nil if %w[XX T1].include?(country_code)
    city = request.headers["CF-IPCity"].to_s.strip.first(60).presence
    country = country_code && country_name(country_code)
    [ city, country ].compact.join(", ").presence
  end

  def self.country_name(code)
    City.where(country_code: code).pick(:country_name) || code
  rescue StandardError
    code
  end

  # "Chrome on Windows near Lagos, Nigeria"
  def described
    location.present? ? "#{name} near #{location}" : name
  end
end

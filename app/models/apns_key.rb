# frozen_string_literal: true

# The Apple push key (AuthKey_XXXX.p8) from the APNS_KEY environment variable,
# rebuilt into a proper PEM whatever a hosting dashboard did to it on paste:
# real line breaks, literal "\n" (single or double escaped), spaces instead of
# line breaks, surrounding quotes, or the whole file base64-encoded.
module ApnsKey
  HEADER = "-----BEGIN PRIVATE KEY-----"
  FOOTER = "-----END PRIVATE KEY-----"

  module_function

  def pem(raw = ENV["APNS_KEY"])
    text = raw.to_s.strip.delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'")
    return "" if text.empty?

    text = text.gsub(/\\+r/, "").gsub(/\\+n/, "\n")
    unless text.include?("BEGIN")
      decoded = Base64.decode64(text) rescue ""
      text = decoded if decoded.include?("BEGIN PRIVATE KEY")
    end

    body = text.sub(/.*?-----BEGIN PRIVATE KEY-----/m, "").sub(/-----END PRIVATE KEY-----.*/m, "")
    body = body.gsub(/[^A-Za-z0-9+\/=]/, "")
    # Pasted without the BEGIN line, a stray "n" (from "\n") can lead the body;
    # every Apple .p8 key body starts with "MIG".
    body = body[body.index("MIG")..] if !text.include?("BEGIN") && body.index("MIG").to_i.between?(1, 3)
    "#{HEADER}\n#{body.scan(/.{1,64}/).join("\n")}\n#{FOOTER}\n"
  end

  # What's wrong with the pasted key, without revealing it (Admin → Push test).
  # A P-256 .p8 key is 200 base64 characters between the markers.
  def describe(raw = ENV["APNS_KEY"])
    text = raw.to_s
    body = pem(raw).lines[1..-2].to_a.join.delete("\n")
    "#{text.length} characters pasted; " \
      "start marker #{text.include?('BEGIN PRIVATE KEY') ? 'found' : 'missing'}, " \
      "end marker #{text.include?('END PRIVATE KEY') ? 'found' : 'missing'}; " \
      "key body #{body.length} of 200 characters"
  end

  # True when the key parses (Admin → Push test shows this).
  def readable?(raw = ENV["APNS_KEY"])
    OpenSSL::PKey.read(pem(raw)).is_a?(OpenSSL::PKey::EC)
  rescue OpenSSL::PKey::PKeyError, ArgumentError
    false
  end
end

# frozen_string_literal: true

require "test_helper"

# Hatchbox (or any dashboard) can mangle a pasted .p8 key: Admin → Push test
# showed "PKeyError: invalid curve name". Every common form must still parse.
class ApnsKeyTest < ActiveSupport::TestCase
  KEY = OpenSSL::PKey::EC.generate("prime256v1")
  PEM = KEY.private_to_pem

  def assert_reads(raw, what)
    assert ApnsKey.readable?(raw), "couldn't read the key #{what}"
    assert_equal KEY.private_to_der, OpenSSL::PKey.read(ApnsKey.pem(raw)).private_to_der
  end

  test "reads the key however it was pasted" do
    assert_reads PEM, "as the file"
    assert_reads PEM.gsub("\n", "\\n"), "with literal \\n"
    assert_reads PEM.gsub("\n", "\\\\n"), "with double-escaped \\\\n"
    assert_reads PEM.gsub("\n", " "), "with spaces for line breaks"
    assert_reads PEM.gsub("\n", ""), "on one line with no breaks"
    assert_reads %("#{PEM.gsub("\n", "\\n")}"), "in quotes"
    assert_reads PEM.gsub("\n", "\r\n"), "with Windows line breaks"
    assert_reads Base64.strict_encode64(PEM), "base64-encoded"
    body = PEM.lines[1..-2].join
    assert_reads body, "without the BEGIN/END lines"
    assert_reads "n" + body.gsub("\n", "\\n").chomp("\\n"), "without BEGIN/END, with a stray n (as found on the server)"
  end

  test "an empty or broken key isn't readable" do
    assert_not ApnsKey.readable?("")
    assert_not ApnsKey.readable?(nil)
    assert_not ApnsKey.readable?("-----BEGIN PRIVATE KEY-----\nnot a key\n-----END PRIVATE KEY-----")
  end
end

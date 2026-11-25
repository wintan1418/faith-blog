# frozen_string_literal: true

require "test_helper"

class DeviceInfoTest < ActiveSupport::TestCase
  test "names browsers, systems and the apps in plain words" do
    {
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36" => "Chrome on Windows",
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1" => "Safari on iPhone",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15" => "Safari on Mac",
      "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/26.0 Chrome/122.0 Mobile Safari/537.36" => "Samsung Internet on Android",
      "Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0 Safari/537.36 Edg/131.0" => "Edge on Windows",
      "Mozilla/5.0 (X11; Linux x86_64; rv:133.0) Gecko/20100101 Firefox/133.0" => "Firefox on Linux",
      "Brethreign/1.0.13 Hotwire Native Android; Turbo Native Android" => "Brethreign app on Android",
      "Brethreign/1.0.9; NativeAppleSignIn; Hotwire Native iOS; Turbo Native iOS (iPhone)" => "Brethreign app on iPhone",
      "" => "Unknown device"
    }.each { |ua, name| assert_equal name, DeviceInfo.name_for(ua), ua }
  end

  test "the place comes only from Cloudflare's headers" do
    request = ActionDispatch::TestRequest.create("HTTP_CF_IPCOUNTRY" => "NG", "HTTP_CF_IPCITY" => "Lagos")
    assert_equal "Lagos, Nigeria", DeviceInfo.location_for(request)
    assert_nil DeviceInfo.location_for(ActionDispatch::TestRequest.create("HTTP_CF_IPCOUNTRY" => "XX"))
  end
end

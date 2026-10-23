# frozen_string_literal: true

# Files phones fetch from /.well-known to trust that brethreign.com links may
# open in the Brethreign app instead of the browser.
class WellKnownController < ApplicationController
  ANDROID_PACKAGE = "com.brethreign.app"

  # SHA-256 fingerprints of the keys the Android app is signed with:
  # Google Play's app signing key (Play installs) and our upload key (direct installs).
  ANDROID_CERT_FINGERPRINTS = [
    "DB:02:1B:A8:7B:D4:5E:44:42:E7:B7:DF:AD:47:D3:66:69:5D:DB:37:6F:F0:90:29:46:5A:D5:DB:8B:3C:82:6A",
    "CC:2D:4E:52:81:38:0B:78:BF:29:4D:3C:B0:69:84:C6:70:E3:B9:1F:52:A5:61:37:B8:D1:CC:0C:35:4E:6E:CD"
  ].freeze

  def assetlinks
    expires_in 1.hour, public: true
    render json: [
      {
        relation: [ "delegate_permission/common.handle_all_urls" ],
        target: {
          namespace: "android_app",
          package_name: ANDROID_PACKAGE,
          sha256_cert_fingerprints: ANDROID_CERT_FINGERPRINTS
        }
      }
    ]
  end
end

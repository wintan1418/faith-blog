# frozen_string_literal: true

require "test_helper"

class AppWaitlistEntryTest < ActiveSupport::TestCase
  test "normalises the email (strip, downcase)" do
    entry = AppWaitlistEntry.create!(email: "  Grace@Example.COM ", platform: "ios")
    assert_equal "grace@example.com", entry.email
  end

  test "one row per email, whatever the case" do
    AppWaitlistEntry.create!(email: "peace@example.com", platform: "ios")
    dup = AppWaitlistEntry.new(email: "PEACE@example.com", platform: "android")
    assert_not dup.valid?

    # The database index backs it up even if validation is skipped.
    assert_raises(ActiveRecord::RecordNotUnique) do
      AppWaitlistEntry.connection.execute(
        "INSERT INTO app_waitlist_entries (email, platform, created_at, updated_at) VALUES ('Peace@Example.com', 'both', now(), now())"
      )
    end
  end

  test "joining again with the same email updates the platform" do
    first = AppWaitlistEntry.join(email: "hope@example.com", platform: "ios", source: "welcome", remote_ip: "1.2.3.4")
    assert first.persisted?

    assert_no_difference "AppWaitlistEntry.count" do
      again = AppWaitlistEntry.join(email: " HOPE@example.com", platform: "android", source: "elsewhere")
      assert_equal first.id, again.id
      assert_equal "android", again.reload.platform
      assert_equal "welcome", again.source # the first source is kept
    end
  end

  test "rejects a badly formed email" do
    %w[not-an-email nobody@nowhere a@b. @example.com].push("two words@example.com").each do |bad|
      entry = AppWaitlistEntry.join(email: bad, platform: "both")
      assert_not entry.persisted?, bad
      assert entry.errors[:email].any?, bad
    end
    assert_not AppWaitlistEntry.join(email: "", platform: "both").persisted?
  end

  test "rejects throwaway email services from the shared blocklist" do
    entry = AppWaitlistEntry.join(email: "someone@mailinator.com", platform: "both")
    assert_not entry.persisted?
    assert_match "throwaway", entry.errors[:email].first
  end

  test "only iPhone, Android or both" do
    assert_not AppWaitlistEntry.new(email: "x@example.com", platform: "blackberry").valid?
    assert AppWaitlistEntry.new(email: "x@example.com", platform: "both").valid?
  end

  test "keeps a keyed hash of the IP, never the IP itself" do
    entry = AppWaitlistEntry.join(email: "ip@example.com", platform: "both", remote_ip: "203.0.113.9")
    assert_match(/\A\h{64}\z/, entry.ip_hash)
    assert_not_includes entry.ip_hash, "203.0.113.9"
  end

  test "platform counts and who to tell per platform" do
    AppWaitlistEntry.create!(email: "a@example.com", platform: "ios")
    AppWaitlistEntry.create!(email: "b@example.com", platform: "both")
    AppWaitlistEntry.create!(email: "c@example.com", platform: "android")

    assert_equal({ "ios" => 1, "android" => 1, "both" => 1 }, AppWaitlistEntry.platform_counts)
    assert_equal %w[a@example.com b@example.com], AppWaitlistEntry.for_platform(:ios).order(:email).pluck(:email)
  end
end

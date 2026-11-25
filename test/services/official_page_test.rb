# frozen_string_literal: true

require "test_helper"

# bin/rails pages:official: the @brethreign page, verified, owned by the founder.
class OfficialPageTest < ActiveSupport::TestCase
  setup { ENV["AI_MODERATION_STUB"] = "1" }
  teardown { ENV.delete("AI_MODERATION_STUB") }

  def run_task(**options)
    out = StringIO.new
    OfficialPage.new(owner: "wintan", logo: Rails.root.join("public/icon.png").to_s, out: out, **options).call
    out.string
  end

  test "dry run changes nothing; APPLY creates it once and re-running is safe" do
    founder = create_member("wintan")
    founder.profile.update_columns(city_id: cities(:akure).id)

    assert_match(/dry run/, run_task(apply: false))
    assert_equal 0, Page.count

    run_task(apply: true, posts: true)
    page = Page.find_by_handle!("brethreign")
    assert page.verified?
    assert page.owner?(founder)
    assert page.logo.attached?
    assert_equal cities(:akure), page.city
    assert_equal "Work, life and faith, talked about kindly.", page.tagline
    assert_equal 2, page.posts.count

    output = run_task(apply: true, posts: true)
    assert_match(/already there/, output)
    assert_equal 1, Page.count
    assert_equal 2, page.posts.count
    assert_equal 1, page.memberships.count
  end

  test "no such owner: nothing happens" do
    assert_match(/No member called/, run_task(apply: true))
    assert_equal 0, Page.count
  end
end

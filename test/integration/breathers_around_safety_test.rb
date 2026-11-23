# frozen_string_literal: true

require "test_helper"

# Breathers around you safety: no town-hopping, nobody singled out in a small
# place, no online dots, seeing requires showing, new accounts wait a week,
# a daily cap on hellos to strangers, Report / Block / Hide me, and members who
# stopped coming drop out.
class BreathersAroundSafetyTest < ActionDispatch::IntegrationTest
  def placed(name, city, **attrs)
    create_member(name).tap { |user| user.profile.update!(city: city, show_in_nearby: true, **attrs) }
  end

  def names_on_page = css_select(".ba-person .ba-person-name").map { |n| n.text.strip }

  def chips = css_select(".ba-person .ba-chips .ba-chip:first-child").map { |d| d.text.strip }

  def map_dots = JSON.parse(css_select("[data-around-map-dots-value]").first["data-around-map-dots-value"])

  def town(name, lat:, lng:, population:, admin1: "Ondo State", geonames_id: rand(90_000_000..99_999_999))
    City.create!(geonames_id: geonames_id, name: name, ascii_name: name, admin1_code: "48", admin1_name: admin1,
                 country_code: "NG", country_name: "Nigeria", lat: lat, lng: lng, population: population)
  end

  def complete_card(user)
    user.brethren_card.update!(church_or_assembly: "Grace Assembly", bio: "Hello", occupation: "Builder",
                               whatsapp_number: "+2348012345678", email: user.email)
  end

  setup do
    @me = placed("viewer", cities(:akure)).tap { |u| u.update_columns(created_at: 30.days.ago) }
    sign_in @me
  end

  # 1. Teleporting -------------------------------------------------------------

  test "a member can change city twice in 30 days; the third is refused with the date" do
    patch around_path, params: { profile: { city_id: cities(:owo).id } }
    assert_equal cities(:owo), @me.profile.reload.city
    patch around_path, params: { profile: { city_id: cities(:lagos).id } }
    assert_equal cities(:lagos), @me.profile.reload.city

    patch around_path, params: { profile: { city_id: cities(:ondo).id } }
    assert_redirected_to city_around_path
    follow_redirect!
    first_change = CityChange.where(user: @me, counted: true).order(:created_at).first.created_at
    date = (first_change + 30.days).to_date.to_fs(:long)
    assert_includes flash[:alert], "You can change it again on #{date}"
    assert_select ".ba-city-limit", text: /You can change it again on #{date}/
    assert_equal cities(:lagos), @me.profile.reload.city

    # The settings form (typed location) is held to the same limit.
    patch settings_profile_path, params: { profile: { location: "Ondo, Nigeria" } }
    assert_response :unprocessable_entity
    assert_equal cities(:lagos), @me.profile.reload.city

    travel 31.days do
      patch around_path, params: { profile: { city_id: cities(:ondo).id } }
      assert_equal cities(:ondo), @me.profile.reload.city
    end
  end

  test "a first city and clearing it are free, but clearing then picking another counts" do
    member = create_member("mover")
    profile = member.profile
    profile.update!(city: cities(:akure))   # first city: free
    profile.update!(city: nil, location: nil) # clearing: free
    profile.update!(city: cities(:owo))     # after having one: counted
    profile.update!(city: cities(:lagos))   # counted
    refute profile.update(city: cities(:ondo))
    assert_match(/You can change it again on/, profile.errors.full_messages.to_sentence)

    trail = CityChange.where(user: member).order(:id).pluck(:from_city_id, :to_city_id, :counted)
    assert_equal [ [ nil, cities(:akure).id, false ], [ cities(:akure).id, nil, false ],
                   [ nil, cities(:owo).id, true ], [ cities(:owo).id, cities(:lagos).id, true ] ], trail
  end

  test "staff see members with 3+ city changes in 30 days" do
    mover = create_member("hopper")
    mover.profile.update!(city: cities(:akure))
    mover.profile.update!(city: nil, location: nil)
    mover.profile.update!(city: cities(:owo))
    create_member("settled").profile.update!(city: cities(:lagos))

    assert_equal({ mover.id => 3 }, CityChange.frequent_movers)

    get admin_city_changes_path
    assert_redirected_to root_path, "members can't see it"

    admin = create_member("staff", role: :admin)
    sign_in admin
    get admin_city_changes_path
    assert_response :success
    assert_select "#city-movers td", text: "@hopper"
    assert_select "#city-movers td", text: "@settled", count: 0
  end

  test "the city picker only counts breathers in big places near your own city" do
    3.times do |i|
      placed("aku#{i}", cities(:akure))
      placed("tor#{i}", cities(:toronto))
      placed("lag#{i}", cities(:lagos))
    end
    placed("owo_one", cities(:owo))

    counts = ->(q) { get(cities_path(q: q)); response.parsed_body.to_h { |c| [ c["name"], c["breathers"] ] } }
    assert_equal 3, counts.call("aku")["Akure"]
    assert_equal 0, counts.call("tor")["Toronto"], "Toronto is far away"
    assert_equal 0, counts.call("lagos, nigeria")["Lagos"], "Lagos is ~250 km away"
    assert_equal 0, counts.call("owo")["Owo"], "one person is never counted on their own"

    @me.profile.update!(show_in_nearby: false)
    assert_equal 0, counts.call("aku")["Akure"], "no counts until you show yourself"
  end

  # 2. Small towns and the rule of three ------------------------------------------

  test "members in a small town are shown near the nearest big city, everywhere" do
    iju = town("Iju", lat: 7.32, lng: 5.25, population: 20_000) # ~10 km from Akure
    @me.profile.update!(city: cities(:owo)) # ~44 km from Akure
    3.times { |i| placed("iju#{i}", iju) }

    get around_path
    assert_equal %w[iju2 iju1 iju0], names_on_page
    assert_equal [ "near Akure · ~40 km" ], chips.uniq
    assert_select ".ba-section--near"
    dots = map_dots
    assert_equal [ "Akure", "Owo" ], dots.map { |d| d["name"] }.sort
    assert_equal 3, dots.find { |d| d["name"] == "Akure" }["count"]
    assert_not_includes response.body, "Iju"

    # Someone living in the small town sees their place as "in and around Akure".
    local = placed("iju_viewer", iju).tap { |u| u.update_columns(created_at: 30.days.ago) }
    sign_in local
    get around_path
    assert_select ".ba-section--same_city .ba-section-title", text: "In and around Akure"
    # (The one member in Owo is alone there, so only the region shows.)
    assert_equal [ "Ondo State · Within 50 km", "near Akure" ], chips.uniq.sort
    get feed_path
    assert_select ".ba-feed-title", text: "3 breathers live in and around Akure"
    assert_not_includes response.body.gsub(/Iju, Ondo, Nigeria/, ""), "Iju · "
  end

  test "a small town with no big city nearby keeps its name only with 3+, otherwise shows the region" do
    remote = town("Faraway", lat: 9.9, lng: 3.0, population: 4_000, admin1: "Kwara State")
    placed("lonely", remote)

    get around_path
    assert_equal [ "lonely" ], names_on_page
    assert_equal [ "Kwara State · Same country" ], chips
    assert_not_includes response.body, "Faraway"
    assert_not(map_dots.any? { |d| d["name"] == "Faraway" })

    2.times { |i| placed("far#{i}", remote) }
    get around_path
    assert_equal [ "Faraway · Same country" ], chips.uniq
    assert_equal 3, map_dots.find { |d| d["name"] == "Faraway" }["count"]
  end

  test "fewer than 3 in your city: no 'In Akure' section, no city dot, and the feed card goes wider" do
    placed("one", cities(:akure))
    placed("two", cities(:akure))

    get around_path
    assert_select ".ba-section--same_city", count: 0
    assert_select ".ba-section--near .ba-person-name", count: 2
    assert_equal [ "Ondo State · Within 50 km" ], chips.uniq
    mine = map_dots.find { |d| d["mine"] }
    assert_equal 0, mine["count"], "your own dot doesn't say 2 live there"
    assert_equal 1, map_dots.size

    get feed_path
    assert_select ".ba-feed-title", text: "2 breathers live within 50 km of you"

    placed("three", cities(:akure))
    get around_path
    assert_select ".ba-section--same_city .ba-section-title", text: "In Akure"
    assert_equal [ "Same city" ], chips.uniq
    assert_equal 3, map_dots.find { |d| d["mine"] }["count"]
    get feed_path
    assert_select ".ba-feed-title", text: "3 breathers live in Akure"
  end

  test "single members in different towns fold into one dot for their region" do
    placed("in_ondo", cities(:ondo))
    placed("in_owo", cities(:owo))
    placed("in_akure", cities(:akure))

    get around_path
    names = map_dots.reject { |d| d["mine"] }.map { |d| d["name"] }
    assert_equal [ "Ondo State" ], names
    assert_equal 3, map_dots.find { |d| d["name"] == "Ondo State" }["count"]
    refute(map_dots.any? { |d| %w[Ondo Owo].include?(d["name"]) })
    assert_equal [ "Ondo State · Within 50 km" ], chips.uniq.reject { |c| c.include?("Same country") }
  end

  # 3. No online dot ---------------------------------------------------------------------

  test "cards never show who is online now" do
    3.times { |i| placed("online#{i}", cities(:akure)).update_columns(last_seen_at: Time.current) }

    get around_path
    assert_equal 3, names_on_page.size
    assert_select ".ba-online", count: 0
    assert_not_includes response.body, "Online now"
    assert_not_includes response.body, "Last seen"
  end

  # 4. Seeing requires showing; new accounts wait a week ------------------------------------

  test "members who show their city to nobody see the opt-in screen, and the feed card has no faces" do
    3.times { |i| placed("nb#{i}", cities(:akure)) }
    @me.profile.update!(city_visibility: :only_me)

    get around_path
    assert_select ".ba-optin-sheet"
    assert_empty names_on_page

    @me.profile.update!(city_visibility: :everyone, show_in_nearby: false)
    get feed_path
    assert_select ".ba-feed-title", text: "3 breathers live in Akure"
    assert_select ".ba-feed-face", count: 0
    assert_select ".ba-feed-names", text: /Turn on Show me/
  end

  test "accounts under a week old get a friendly wait page; admins can always look" do
    3.times { |i| placed("nb#{i}", cities(:akure)) }
    @me.update_columns(created_at: 2.days.ago)

    get around_path
    assert_select "h1", text: "Breathers around you opens after your first week"
    assert_select ".ba-empty-copy", text: /#{(@me.created_at + 7.days).to_date.to_fs(:long)}/
    assert_empty names_on_page
    get cities_path(q: "aku")
    assert_equal 0, response.parsed_body.first["breathers"]
    get feed_path
    assert_select ".ba-feed-face", count: 0
    assert_select ".ba-feed-names", text: /after your first week/

    @me.update_columns(role: User.roles[:admin])
    get around_path
    assert_equal 3, names_on_page.size
  end

  # 5. Hellos to strangers --------------------------------------------------------------

  test "Say hello to strangers is capped at 10 in 24 hours" do
    complete_card(@me)
    strangers = 11.times.map { |i| placed("stranger#{i}", cities(:akure)) }

    strangers.first(10).each do |s|
      post connection_requests_path(receiver_id: s.id, via: "around"), params: { message: "Hi!" }, as: :turbo_stream
      assert_response :success
    end
    assert_equal 10, ConnectionRequest.where(sender: @me, via_around: true).count

    post connection_requests_path(receiver_id: strangers.last.id, via: "around"), params: { message: "Hi!" }, as: :turbo_stream
    assert_response :unprocessable_entity
    assert_includes response.body, "You&#39;ve said hello to 10 new people from Breathers around you today"
    assert_nil ConnectionRequest.find_by(sender: @me, receiver: strangers.last)

    travel 25.hours do
      post connection_requests_path(receiver_id: strangers.last.id, via: "around"), params: { message: "Hi!" }, as: :turbo_stream
      assert ConnectionRequest.exists?(sender: @me, receiver: strangers.last)
    end
  end

  # 6. Report, Block, Hide me, inactivity -------------------------------------------------

  test "every card has Report and Block, and reporting a member reaches the moderators" do
    other = placed("someone", cities(:akure))

    get around_path
    assert_select "##{ActionView::RecordIdentifier.dom_id(other, :around)} .ba-more-menu" do
      assert_select "form[action='#{reports_path}'] input[name=reportable_type][value=User]"
      assert_select "form[action='#{message_blocks_path(user_id: other.id)}']"
    end

    assert_difference -> { Report.where(reportable: other).count } do
      post reports_path, params: { reportable_type: "User", reportable_id: other.id, reason: "Reported from Breathers around you." }
    end
    assert_no_difference -> { Report.count } do
      post reports_path, params: { reportable_type: "User", reportable_id: @me.id, reason: "Reported from Breathers around you." }
    end

    post message_blocks_path(user_id: other.id)
    get around_path
    assert_not_includes names_on_page, "someone"
  end

  test "Hide me turns you off in one tap and closes the list" do
    3.times { |i| placed("nb#{i}", cities(:akure)) }
    get around_path
    assert_select "form[action='#{around_path}'] button.ba-hide-me", text: /Hide me/

    patch around_path, params: { profile: { show_in_nearby: "0" } }
    refute @me.profile.reload.show_in_nearby?
    follow_redirect!
    assert_select ".ba-optin-sheet"
    assert_empty names_on_page
  end

  test "members who haven't been on for 60 days drop out" do
    placed("recent", cities(:akure)).update_columns(last_seen_at: 59.days.ago)
    placed("gone_quiet", cities(:akure)).update_columns(last_seen_at: 61.days.ago)
    placed("never_seen_old", cities(:akure)).update_columns(last_seen_at: nil, created_at: 90.days.ago)
    placed("never_seen_new", cities(:akure)).update_columns(last_seen_at: nil)

    get around_path
    assert_equal %w[never_seen_new recent], names_on_page.sort
  end
end

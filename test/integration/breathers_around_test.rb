# frozen_string_literal: true

require "test_helper"

# "Breathers around you": the privacy rules, checked through the real pages.
class BreathersAroundTest < ActionDispatch::IntegrationTest
  def placed(name, city, **profile)
    create_member(name).tap do |user|
      user.profile.update!(city: city, show_in_nearby: true, **profile.except(:birth_year))
      user.profile.update_columns(profile.slice(:birth_year)) if profile.key?(:birth_year)
    end
  end

  def names_on_page = css_select(".ba-person .ba-person-name").map { |n| n.text.strip }

  def map_dots = JSON.parse(css_select("[data-around-map-dots-value]").first["data-around-map-dots-value"])

  setup do
    @me = placed("viewer", cities(:akure))
    sign_in @me
  end

  test "lists people by same city, within 50 km, then the same country, with bucketed distances" do
    placed("same_city", cities(:akure))
    placed("in_owo", cities(:owo))
    placed("in_lagos", cities(:lagos))
    placed("in_toronto", cities(:toronto))

    get around_path
    assert_response :success
    assert_select ".ba-section--same_city .ba-person-name", text: "same_city"
    assert_select ".ba-section--near .ba-person-name", text: "in_owo"
    assert_select ".ba-section--country .ba-person-name", text: "in_lagos"
    refute_includes names_on_page, "in_toronto"

    distances = css_select(".ba-person .ba-chips .ba-chip:first-child").map { |d| d.text.strip }
    assert_equal [ "Same city", "Owo · ~40 km", "Lagos · Same country" ], distances
    # Never more precise than a city: no exact kilometres (Owo is ~44 km away).
    refute_match(/\b4[1-9] km\b/, response.body)
  end

  test "opted-out, blocked (either way), under-18, deactivated and hidden members never appear" do
    placed("visible", cities(:akure))
    placed("opted_out", cities(:akure)).profile.update!(show_in_nearby: false)
    MessageBlock.create!(blocker: @me, blocked: placed("i_blocked", cities(:akure)))
    MessageBlock.create!(blocker: placed("blocked_me", cities(:akure)), blocked: @me)
    placed("teen", cities(:akure), birth_year: Date.current.year - 16)
    placed("gone", cities(:akure)).update!(active: false)
    placed("only_me", cities(:akure), city_visibility: :only_me)
    placed("friends_only", cities(:akure), city_visibility: :connections)

    get around_path
    assert_equal [ "visible" ], names_on_page

    # Counts and map dots (worldwide, one per city) follow the same rules.
    assert_select ".ba-section-count", text: "1 breather"
    assert_equal [ 1 ], map_dots.map { |d| d["count"] }
    assert_equal [ "name", "lat", "lng", "count", "mine", "near", "country", "distance" ].sort, map_dots.first.keys.sort
  end

  test "connections-only members appear to their connections" do
    friend = placed("friend", cities(:akure), city_visibility: :connections)
    ConnectionRequest.new(sender: @me, receiver: friend, status: :accepted).save!(validate: false)

    get around_path
    assert_equal [ "friend" ], names_on_page
    assert_select ".ba-person-action button", text: "Message"
  end

  test "Say hello to a stranger is a connection request under the usual rules" do
    other = placed("stranger", cities(:akure))
    @me.brethren_card.update!(church_or_assembly: "Grace Assembly", bio: "Hello", occupation: "Builder",
                              whatsapp_number: "+2348012345678", email: @me.email)

    get around_path
    button = css_select(".ba-person-action button").first
    assert_equal "Say hello", button.text.strip
    person = JSON.parse(button["data-around-hello-person-param"])
    assert_equal "request", person["mode"]
    assert_equal connection_requests_path(receiver_id: other.id), person["request_url"]
    assert_equal 3, person["lines"].size

    # The note rides along with the connection request.
    post connection_requests_path(receiver_id: other.id, message: person["lines"].first), as: :turbo_stream
    assert_equal person["lines"].first, ConnectionRequest.find_by(sender: @me, receiver: other).message
  end

  test "first visit asks you to opt in; you can just look around, hidden, or turn it on" do
    @me.profile.update!(show_in_nearby: false)
    placed("neighbour", cities(:akure))
    placed("near_owo", cities(:owo))

    get around_path
    assert_select ".ba-optin-copy", text: /2 breathers live within 50 km of Akure/
    assert_select ".ba-optin-sheet button", text: "Show me to breathers near me"
    assert_empty names_on_page

    patch around_path, params: { look_around: "1" }
    follow_redirect!
    assert_equal [ "neighbour", "near_owo" ], names_on_page
    assert_select ".ba-hidden-note"
    refute @me.profile.reload.show_in_nearby?, "looking around never opts you in"

    get around_path
    assert_select ".ba-optin-sheet", count: 0

    patch around_path, params: { profile: { show_in_nearby: "1" } }
    assert @me.profile.reload.show_in_nearby?
    follow_redirect!
    assert_select ".ba-hidden-note", count: 0
  end

  test "without a city the page sends you to pick one, and picking one stores only the city" do
    @me.profile.update!(city: nil, location: nil, show_in_nearby: false)
    get around_path
    assert_redirected_to city_around_path
    follow_redirect!
    assert_select "input[name='profile[city_id]'][type=hidden]"
    assert_select "input[type=checkbox][role=switch][name='profile[show_in_nearby]']"

    patch around_path, params: { profile: { city_id: cities(:owo).id, location: "Owo, Ondo, Nigeria", show_in_nearby: "0" } }
    assert_equal cities(:owo), @me.profile.reload.city
    assert_equal "Owo, Ondo, Nigeria", @me.profile.location
    refute @me.profile.show_in_nearby?, "picking a city must not opt you in"
  end

  test "Say hello to a connection sends a message; to anyone else it can't" do
    friend = placed("friend", cities(:akure))
    stranger = placed("stranger", cities(:akure))
    ConnectionRequest.new(sender: @me, receiver: friend, status: :accepted).save!(validate: false)

    post around_hello_path, params: { recipient_id: friend.id, body: "Hi friend! I saw you're in Akure too." }
    conversation = Conversation.joins(:conversation_participants).where(conversation_participants: { user_id: friend.id })
                               .merge(@me.conversations).first
    assert_redirected_to conversation_path(conversation)
    assert_equal "Hi friend! I saw you're in Akure too.", conversation.messages.last.body

    assert_no_difference -> { Message.count } do
      post around_hello_path, params: { recipient_id: stranger.id, body: "Hi" }
    end
    assert_redirected_to around_path
  end

  test "under-18 members can't use the page or opt in" do
    @me.profile.update_columns(birth_year: Date.current.year - 15, show_in_nearby: false)
    placed("adult", cities(:akure))

    get around_path
    assert_select "h1", text: /18 and over/
    assert_empty names_on_page

    patch around_path, params: { profile: { show_in_nearby: "1" } }
    refute @me.profile.reload.show_in_nearby?
  end

  test "filters: open to mentoring (as shown to you), industry and room" do
    mentor = placed("mentor", cities(:akure), open_to: [ "mentoring" ], industry: "Education")
    placed("hidden_mentor", cities(:akure), open_to: [ "mentoring" ], open_to_visibility: :connections)
    placed("coder", cities(:owo), industry: "Software Development")
    room = Room.create!(name: "Akure Youth", description: "x", room_type: :general, is_public: true)
    RoomMembership.create!(room: room, user: mentor)
    RoomMembership.create!(room: room, user: @me)

    get around_path(filter: "mentoring")
    assert_equal [ "mentor" ], names_on_page
    get around_path(industry: "Software Development")
    assert_equal [ "coder" ], names_on_page
    get around_path(filter: "rooms")
    assert_equal [ "mentor" ], names_on_page
    assert_select ".ba-chip.is-blue", text: "Both in Akure Youth"
    # Industry pills come from what nearby people do.
    assert_select ".ba-filters a", text: "Software Development"
  end

  test "city type-ahead and nearest city; the position is used once and never kept" do
    placed("neighbour", cities(:akure))
    get cities_path(q: "aku")
    assert_equal "Akure, Ondo, Nigeria", response.parsed_body.first["label"]
    assert_equal 1, response.parsed_body.first["breathers"]

    before = @me.profile.reload.attributes
    post nearest_city_path, params: { lat: "7.20", lng: "5.59" }
    assert_equal cities(:owo).id, response.parsed_body["id"]
    assert_equal before, @me.profile.reload.attributes, "looking up the nearest city changes nothing"
    filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
                                            .filter("lat" => "7.20", "lng" => "5.59", "latest" => "x")
    assert_equal({ "lat" => "[FILTERED]", "lng" => "[FILTERED]", "latest" => "x" }, filtered)
  end

  test "the type-ahead needs a signed-in member" do
    sign_out @me
    get cities_path(q: "aku")
    assert_response :unauthorized
  end

  test "settings: picking a city, visibility and the opt-in from the profile form" do
    @me.profile.update!(city: nil, location: nil, show_in_nearby: false)
    patch settings_profile_path, params: { profile: { location: "Toronto, Ontario, Canada", city_id: cities(:toronto).id,
                                                      city_visibility: "connections", show_in_nearby: "1" } }
    profile = @me.profile.reload
    assert_equal cities(:toronto), profile.city
    assert profile.city_shown_to_connections?
    assert profile.show_in_nearby?
  end

  test "the profile hides a city kept for connections from strangers" do
    other = create_member("other")
    other.profile.update!(city: cities(:lagos), city_visibility: :connections)

    get user_path(other.username)
    assert_not_includes response.body, "Lagos, Nigeria"
    other.profile.update!(city_visibility: :everyone)
    get user_path(other.username)
    assert_includes response.body, "Lagos, Nigeria"
  end

  test "feed card: how many live in your city, or a nudge to add one" do
    placed("neighbour", cities(:akure))
    placed("neighbour2", cities(:akure))
    get feed_path
    assert_select ".ba-feed-title", text: "2 breathers live in Akure"
    assert_select ".ba-feed-face", count: 2

    @me.profile.update!(city: cities(:toronto))
    get feed_path
    assert_select ".ba-feed-card", count: 0

    @me.profile.update!(city: nil, location: nil)
    get feed_path
    assert_select ".ba-feed-add-title", text: "Add your city to find breathers around you"
  end

  test "anonymous breaths never carry a place" do
    room = Room.create!(name: "Prayer Wall", description: "x", room_type: :general, is_public: true)
    breath = Post.create!(user: @me, room: room, title: "Please pray", content: "A hard season",
                          status: :published, moderation_status: :approved, anonymous: true)
    sign_in create_member("reader", tour_completed_at: Time.current, welcomed_at: Time.current)
    get post_path(breath)
    assert_response :success
    assert_not_includes response.body, "Akure"
  end
end

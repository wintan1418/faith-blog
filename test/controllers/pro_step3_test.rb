# frozen_string_literal: true

require "test_helper"

# Professional step 3: "Open to", skill endorsements, the digital business card.
class ProStep3Test < ActionDispatch::IntegrationTest
  def connect(a, b)
    ConnectionRequest.new(sender: a, receiver: b, status: :accepted).save!(validate: false)
  end

  setup do
    @ada = create_member("st3_ada")
    @ben = create_member("st3_ben")
    @ada.profile.update!(skills_list: "UX design, Figma", headline: "Product designer")
    @ada.experiences.create!(title: "Product Designer", organization: "Lumen Pay", start_month: "2023-03", current: true)
  end

  # ── Open to ──────────────────────────────────────────────────────
  test "choosing Open to puts a ring and badge on your photo for everyone" do
    sign_in @ada
    patch settings_professional_path, params: { profile: { open_to: [ "", "mentoring", "work", "nonsense" ], open_to_visibility: "everyone" } }
    assert_equal %w[work mentoring], @ada.profile.reload.open_to # list order, unknown values dropped

    sign_in @ben
    get user_path(@ada.username)
    assert_select ".profile-avatar-wrap.ot-ring.ot-ring--blue"
    assert_select ".ot-badge", text: "Open to work"
    get user_path(@ada.username, tab: "professional")
    assert_select ".ot-card .ot-chip", count: 2
  end

  test "Open to for connections only stays hidden from everyone else" do
    @ada.profile.update!(open_to: %w[work], open_to_visibility: "connections")

    sign_in @ben
    get user_path(@ada.username)
    assert_select ".ot-badge", count: 0
    assert_select ".profile-avatar-wrap.ot-ring", count: 0

    connect(@ada, @ben)
    get user_path(@ada.username)
    assert_select ".ot-badge", text: "Open to work"
  end

  test "unticking everything clears Open to" do
    @ada.profile.update!(open_to: %w[hiring])
    sign_in @ada
    patch settings_professional_path, params: { profile: { open_to: [ "" ] } }
    assert_empty @ada.profile.reload.open_to
  end

  # ── Endorsements ─────────────────────────────────────────────────
  test "a connection can endorse a skill once, and take it back" do
    connect(@ada, @ben)
    sign_in @ben
    get user_path(@ada.username, tab: "professional")
    assert_select ".sk-row", count: 2
    assert_select "form[action=?] button", endorse_skill_path(@ada.username, skill: "UX design"), text: "+ Endorse"

    post endorse_skill_path(@ada.username, skill: "ux design"), as: :turbo_stream
    assert_response :success
    assert_match "✓ Endorsed", response.body
    endorsement = @ada.skill_endorsements.sole
    assert_equal "UX design", endorsement.skill # stored as the member wrote it
    assert @ada.notifications.where(notification_type: :skill_endorsed, actor: @ben).exists?

    post endorse_skill_path(@ada.username, skill: "UX design"), as: :turbo_stream
    assert_equal 1, @ada.skill_endorsements.count

    get user_path(@ada.username, tab: "professional")
    assert_select ".sk-meta", text: /Endorsed by st3_ben/

    delete unendorse_skill_path(@ada.username, skill: "UX design"), as: :turbo_stream
    assert_empty @ada.skill_endorsements.reload
  end

  test "only connections can endorse, never yourself, and only listed skills" do
    sign_in @ben
    get user_path(@ada.username, tab: "professional")
    assert_select ".sk-btn", count: 0
    post endorse_skill_path(@ada.username, skill: "UX design"), as: :turbo_stream
    assert_empty @ada.skill_endorsements

    connect(@ada, @ben)
    post endorse_skill_path(@ada.username, skill: "Juggling"), as: :turbo_stream
    assert_empty @ada.skill_endorsements

    sign_in @ada
    post endorse_skill_path(@ada.username, skill: "UX design"), as: :turbo_stream
    assert_empty @ada.skill_endorsements
  end

  test "the most-endorsed skill comes first" do
    connect(@ada, @ben)
    SkillEndorsement.create!(user: @ada, endorser: @ben, skill: "Figma")
    sign_in @ben
    get user_path(@ada.username, tab: "professional")
    assert_select ".sk-row:first-child .sk-name", text: "Figma"
  end

  # ── The card ─────────────────────────────────────────────────────
  test "the card shows a QR code and a summary to anyone, and the owner can change its colour" do
    get card_path(@ada.username)
    assert_response :success
    assert_select ".bcard .bcard-name", text: @ada.display_name
    assert_select ".card-qr-box svg path"
    assert_select "meta[name=robots][content=noindex]"
    assert_select ".card-summary", text: /Product Designer/
    assert_select ".card-styles", count: 0

    sign_in @ada
    get card_path(@ada.username)
    assert_select ".card-styles .card-swatch", count: 4
    patch card_style_path(@ada.username, card_style: "gold")
    assert_equal "gold", @ada.profile.reload.card_style
    patch card_style_path(@ada.username, card_style: "neon")
    assert_equal "gold", @ada.profile.reload.card_style

    sign_in @ben
    patch card_style_path(@ada.username, card_style: "light")
    assert_response :forbidden
  end

  test "Save contact gives a vCard with professional details only" do
    (@ada.brethren_card || @ada.build_brethren_card).update!(whatsapp_number: "+2348000000000", email: "private@example.com", church_or_assembly: "X", occupation: "Y", bio: "Private bio")
    get card_path(@ada.username, format: :vcf)
    assert_response :success
    assert_equal "text/vcard", response.media_type
    assert_match "TITLE:Product Designer", response.body
    assert_match "ORG:Lumen Pay", response.body
    assert_match "URL:#{card_url(@ada.username)}", response.body
    assert_no_match(/2348000000000|private@example.com/, response.body)
  end

  test "a private profile's card is for connections only" do
    @ada.profile.update!(public_profile: false)
    get card_path(@ada.username)
    assert_response :not_found

    sign_in @ben
    connect(@ada, @ben)
    get card_path(@ada.username)
    assert_response :success
  end
end

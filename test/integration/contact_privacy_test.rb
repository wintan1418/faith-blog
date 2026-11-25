# frozen_string_literal: true

require "test_helper"

# Contact details (Brethren Card email and WhatsApp) are private by default and
# reach only the people the member chooses: the visibility matrix for the card,
# the business card and its vCard, "Share my contact", the settings, and the
# places the audit found contact details could reach another member.
class ContactPrivacyTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper
  EMAIL = "owner.private@example.org"
  PHONE = "+234 800 000 1111"
  SEEN = { welcomed_at: Time.current, tour_completed_at: Time.current, onboarding_dismissed_at: Time.current }.freeze

  setup do
    @stub_was = ENV["AI_MODERATION_STUB"]
    ENV["AI_MODERATION_STUB"] = "1"
    @owner = create_member("cp_owner", **SEEN)
    @chosen = create_member("cp_chosen", **SEEN)          # a connection on the owner's list
    @connection = create_member("cp_connection", **SEEN)  # a connection, not on the list
    @stranger = create_member("cp_stranger", **SEEN)      # signed in, not connected
    @admin = create_member("cp_admin", role: :admin, **SEEN)
    [ @owner, @chosen, @connection, @stranger ].each { |u| complete_card(u) }
    @owner.brethren_card.update!(email: EMAIL, whatsapp_number: PHONE)
    connect(@owner, @chosen)
    connect(@connection, @owner)
    ContactShare.create!(owner: @owner, viewer: @chosen)
  end

  teardown { ENV["AI_MODERATION_STUB"] = @stub_was }

  def complete_card(user)
    user.brethren_card.update!(church_or_assembly: "Grace Assembly", bio: "A short profile for testing.", occupation: "Builder")
  end

  def connect(a, b)
    ConnectionRequest.new(sender: a, receiver: b, status: :accepted).save!(validate: false)
  end

  def set_visibility(level, field: :both)
    attrs = {}
    attrs[:email_visibility] = level if field.in?([ :both, :email ])
    attrs[:whatsapp_visibility] = level if field.in?([ :both, :whatsapp ])
    @owner.brethren_card.update_columns(attrs)
  end

  VIEWERS = %i[owner chosen connection stranger signed_out admin].freeze

  def as_viewer(who)
    sign_out :user
    user = who == :signed_out ? nil : instance_variable_get("@#{who}")
    sign_in user if user
    user
  end

  # Who sees the contact details at each setting (the rows of the matrix).
  EXPECTED = {
    "only_me"     => %i[owner admin],
    "chosen"      => %i[owner chosen admin],
    "connections" => %i[owner chosen connection admin],
    "everyone"    => %i[owner chosen connection stranger signed_out admin]
  }.freeze

  test "new cards start private and existing data is not shown by default" do
    card = create_member("cp_fresh").brethren_card
    assert card.email_visibility_only_me?
    assert card.whatsapp_visibility_only_me?
  end

  test "model matrix: who can see each contact detail at each setting" do
    EXPECTED.each do |level, allowed|
      set_visibility(level)
      card = BrethrenCard.find(@owner.brethren_card.id)
      VIEWERS.each do |who|
        viewer = who == :signed_out ? nil : instance_variable_get("@#{who}")
        expected = allowed.include?(who)
        assert_equal expected, card.contact_visible_to?(:email, viewer), "email #{level} for #{who}"
        assert_equal expected, card.contact_visible_to?(:whatsapp, viewer), "whatsapp #{level} for #{who}"
      end
    end
  end

  test "each field has its own setting" do
    @owner.brethren_card.update_columns(email_visibility: "only_me", whatsapp_visibility: "connections")
    card = BrethrenCard.find(@owner.brethren_card.id)
    assert_equal({ whatsapp: PHONE }, card.visible_contact_for(@connection))
  end

  test "Brethren Card page shows contact details only to allowed viewers" do
    EXPECTED.each do |level, allowed|
      set_visibility(level)
      VIEWERS.each do |who|
        user = as_viewer(who)
        get brethren_card_path(@owner.username)
        if user.nil?
          assert_redirected_to new_user_session_path, "signed out at #{level}"
          next
        end
        if allowed.include?(who)
          assert_response :success, "#{who} at #{level}"
          assert_includes response.body, EMAIL, "#{who} should see email at #{level}"
          assert_includes response.body, "wa.me/2348000001111", "#{who} should see WhatsApp at #{level}"
        else
          # Connections still see the card itself, without the contact details;
          # strangers are turned away.
          assert_not_includes response.body, EMAIL, "#{who} must not see email at #{level}"
          assert_not_includes response.body, "wa.me/234", "#{who} must not see WhatsApp at #{level}"
        end
      end
    end
  end

  test "a stranger sees only public contact details, not the rest of the card" do
    set_visibility("everyone")
    sign_in @stranger
    get brethren_card_path(@owner.username)
    assert_response :success
    assert_includes response.body, EMAIL
    assert_not_includes response.body, "Grace Assembly"
  end

  test "the chosen list is for connections: a stranger can't be added, and a share stops counting without the connection" do
    sign_in @owner
    assert_no_difference -> { ContactShare.count } do
      post contact_shares_path(user_id: @stranger.id)
    end
    assert_match(/Connect with cp_stranger first/, flash[:alert])

    set_visibility("chosen")
    ConnectionRequest.between(@owner, @chosen).delete
    assert_not BrethrenCard.find(@owner.brethren_card.id).contact_visible_to?(:email, @chosen)
  end

  test "a stranger nobody shared with is turned away from the card" do
    set_visibility("connections")
    sign_in @stranger
    get brethren_card_path(@owner.username)
    assert_redirected_to user_path(@owner.username)
  end

  test "business card HTML and vCard include contact details only for allowed viewers" do
    EXPECTED.each do |level, allowed|
      set_visibility(level)
      VIEWERS.each do |who|
        as_viewer(who)
        get card_path(@owner.username)
        assert_response :success
        html_has = response.body.include?(EMAIL)
        assert_equal allowed.include?(who), html_has, "business card email for #{who} at #{level}"
        assert_equal allowed.include?(who), response.body.include?("wa.me/2348000001111"), "business card WhatsApp for #{who} at #{level}"

        get card_path(@owner.username, format: :vcf)
        assert_response :success
        assert_equal allowed.include?(who), response.body.include?("EMAIL;TYPE=INTERNET:#{EMAIL}"), "vCard email for #{who} at #{level}"
        assert_equal allowed.include?(who), response.body.include?("TEL;TYPE=CELL:#{PHONE}"), "vCard phone for #{who} at #{level}"
      end
    end
  end

  test "the account email never appears on the business card, card or profile" do
    set_visibility("everyone")
    sign_in @stranger
    [ card_path(@owner.username), user_path(@owner.username), user_path(@owner.username, tab: "about"),
      card_path(@owner.username, format: :vcf) ].each do |path|
      get path
      assert_not_includes response.body, @owner.email, path
    end
  end

  test "a block hides contact details even when they are public" do
    set_visibility("everyone")
    MessageBlock.create!(blocker: @owner, blocked: @stranger)
    sign_in @stranger
    get card_path(@owner.username, format: :vcf)
    assert_not_includes response.body, EMAIL
    assert_not ContactShare.exists?(owner: @owner, viewer: @stranger)
  end

  test "blocking removes shares both ways" do
    MessageBlock.create!(blocker: @chosen, blocked: @owner)
    assert_not ContactShare.exists?(owner: @owner, viewer: @chosen)
  end

  test "connections list shows WhatsApp and Email buttons only when allowed" do
    set_visibility("chosen")
    sign_in @chosen
    get my_connections_path
    assert_includes response.body, "mailto:#{EMAIL}"

    sign_in @connection
    get my_connections_path
    assert_response :success
    assert_not_includes response.body, "mailto:#{EMAIL}"
    assert_not_includes response.body, "wa.me/2348000001111"
  end

  test "Share my contact adds the connection, opens a private detail to the list and notifies them" do
    sign_in @owner
    assert_difference -> { ContactShare.count } => 1, -> { @connection.notifications.where(notification_type: :contact_shared).count } => 1 do
      post contact_shares_path(user_id: @connection.id), headers: { "HTTP_REFERER" => user_url(@connection.username) }
    end
    assert_redirected_to user_url(@connection.username)
    card = @owner.brethren_card.reload
    assert card.email_visibility_chosen?, "only me opens to the chosen list, never wider"
    assert card.whatsapp_visibility_chosen?
    assert card.contact_visible_to?(:email, @connection)
    assert_not BrethrenCard.find(card.id).contact_visible_to?(:email, @stranger)

    alert = @connection.notifications.last
    assert_equal "cp_owner shared their contact details with you", alert.web_message
    assert_equal brethren_card_path(@owner.username), alert.target_path

    sign_in @connection
    get brethren_card_path(@owner.username)
    assert_includes response.body, EMAIL
  end

  test "Share my contact never narrows a wider setting" do
    set_visibility("connections")
    sign_in @owner
    post contact_shares_path(user_id: @connection.id)
    assert @owner.brethren_card.reload.email_visibility_connections?
  end

  test "stop sharing takes the person off and removes the alert" do
    sign_in @owner
    post contact_shares_path(user_id: @connection.id)
    share = ContactShare.find_by!(owner: @owner, viewer: @connection)
    delete contact_share_path(share)
    assert_not ContactShare.exists?(share.id)
    assert_not @connection.notifications.where(notification_type: :contact_shared).exists?
    assert_not BrethrenCard.find(@owner.brethren_card.id).contact_visible_to?(:email, @connection)
  end

  test "you can only remove your own shares" do
    share = ContactShare.find_by!(owner: @owner, viewer: @chosen)
    sign_in @stranger
    delete contact_share_path(share)
    assert ContactShare.exists?(share.id)
  end

  test "sharing needs a contact detail, isn't for yourself or blocked members" do
    sign_in @chosen
    post contact_shares_path(user_id: @owner.id)
    assert_redirected_to edit_settings_brethren_card_path(anchor: "contact")
    assert_not ContactShare.exists?(owner: @chosen)

    sign_in @owner
    post contact_shares_path(user_id: @owner.id)
    assert_not ContactShare.exists?(owner: @owner, viewer: @owner)

    MessageBlock.create!(blocker: @connection, blocked: @owner)
    post contact_shares_path(user_id: @connection.id)
    assert_not ContactShare.exists?(owner: @owner, viewer: @connection)
  end

  test "signed-out visitors can't share" do
    post contact_shares_path(user_id: @stranger.id)
    assert_redirected_to new_user_session_path
  end

  test "profile and chat offer Share my contact to connections, then Stop sharing" do
    sign_in @owner
    get user_path(@connection.username)
    assert_select "form[action=?] button", contact_shares_path(user_id: @connection.id), text: /Share my contact/

    get user_path(@stranger.username)
    assert_select "form[action=?]", contact_shares_path(user_id: @stranger.id), count: 0

    get user_path(@chosen.username)
    share = ContactShare.find_by!(owner: @owner, viewer: @chosen)
    assert_select "form[action='#{contact_share_path(share)}'] button", text: /Stop sharing/

    conversation = Conversation.find_or_create_between!(@owner, @connection)
    get conversation_path(conversation)
    assert_select ".msg-menu form button", text: "Share my contact"
  end

  test "Settings → Privacy saves both settings and lists the chosen people" do
    sign_in @owner
    get edit_settings_privacy_path
    assert_response :success
    assert_select "#contact-privacy"
    assert_select "input[name='brethren_card[email_visibility]'][value='only_me'][checked]"
    assert_select ".ctp-person-name", text: @chosen.display_name
    assert_select "select#contact_share_user_id option", text: /cp_connection/

    patch settings_privacy_path, params: { profile: { public_profile: "1" },
                                           brethren_card: { email_visibility: "everyone", whatsapp_visibility: "connections" } }
    assert_redirected_to edit_settings_privacy_path
    card = @owner.brethren_card.reload
    assert card.email_visibility_everyone?
    assert card.whatsapp_visibility_connections?

    patch settings_privacy_path, params: { brethren_card: { email_visibility: "bogus" } }
    assert @owner.brethren_card.reload.email_visibility_everyone?, "unknown values are ignored"
  end

  test "Settings → Privacy works for a member with an unfinished card" do
    fresh = create_member("cp_unfinished", **SEEN)
    sign_in fresh
    get edit_settings_privacy_path
    assert_response :success
    patch settings_privacy_path, params: { brethren_card: { email_visibility: "connections" } }
    assert fresh.brethren_card.reload.email_visibility_connections?
  end

  test "the card editor has the same controls, and contact details are optional" do
    sign_in @owner
    get edit_settings_brethren_card_path
    assert_select "input[name='brethren_card[whatsapp_visibility]']", 4
    patch settings_brethren_card_path, params: { brethren_card: { email: "", whatsapp_number: "", whatsapp_visibility: "connections" } }
    card = @owner.brethren_card.reload
    assert_nil card.email
    assert card.complete?, "a card is complete without contact details"
    assert card.whatsapp_visibility_connections?

    patch settings_brethren_card_path, params: { brethren_card: { email: "not an email" } }
    assert_response :unprocessable_entity
  end

  test "the one-time notice shows until the member opens the setting or dismisses it" do
    @owner.update_column(:contact_privacy_notice_pending, true)
    sign_in @owner
    get feed_path
    assert_select "#contact_privacy_notice", text: /Your contact details are now private/
    assert_select "#contact_privacy_notice a[href='#{edit_settings_privacy_path(anchor: 'contact-privacy')}']"

    get edit_settings_privacy_path
    assert_not @owner.reload.contact_privacy_notice_pending?
    get feed_path
    assert_select "#contact_privacy_notice", 0

    @owner.update_column(:contact_privacy_notice_pending, true)
    post dismiss_contact_notice_settings_privacy_path
    assert_not @owner.reload.contact_privacy_notice_pending?
  end

  test "the migration flags only members who had contact details" do
    migration = Class.new(ActiveRecord::Migration[8.1]) { def exec(sql) = execute(sql) }
    User.update_all(contact_privacy_notice_pending: false)
    @stranger.brethren_card.update_columns(email: nil, whatsapp_number: "  ")
    ActiveRecord::Migration.suppress_messages do
      migration.new.exec(<<~SQL.squish)
        UPDATE users SET contact_privacy_notice_pending = TRUE
        WHERE id IN (SELECT user_id FROM brethren_cards
                     WHERE COALESCE(TRIM(email), '') <> '' OR COALESCE(TRIM(whatsapp_number), '') <> '')
      SQL
    end
    assert @owner.reload.contact_privacy_notice_pending?
    assert_not @stranger.reload.contact_privacy_notice_pending?
  end

  test "JSON renderings never carry emails or contact details" do
    assert_not @owner.as_json.key?("email")
    assert_not @owner.to_json.include?(@owner.email)
    assert_not @owner.brethren_card.to_json.include?(EMAIL)
    assert_not @owner.brethren_card.to_json.include?(PHONE)
  end

  test "mention autocomplete returns no emails" do
    set_visibility("everyone")
    sign_in @stranger
    get "/mentions", params: { q: "cp_" }
    assert_response :success
    assert_not_includes response.body, EMAIL
    assert_not_includes response.body, "@example.com"
  end

  test "people search can't find a member by email or contact details" do
    set_visibility("everyone")
    sign_in @stranger
    get search_path(q: EMAIL, tab: "people")
    assert_response :success
    assert_not_includes response.body, "cp_owner", "no member found by their contact email"
    assert_empty User.member_search("owner.private").to_a
    assert_empty User.member_search(@owner.email).to_a
  end

  test "admins see contact details even at Only me" do
    set_visibility("only_me")
    sign_in @admin
    get brethren_card_path(@owner.username)
    assert_response :success
    assert_includes response.body, EMAIL
  end

  test "the share alert goes to the app and push, not email, and carries no contact details" do
    set_visibility("everyone")
    sign_in @owner
    assert_no_enqueued_emails do
      post contact_shares_path(user_id: @connection.id)
    end
    alert = @connection.notifications.last
    assert_not_includes alert.message, EMAIL
    assert_not_includes alert.message, @owner.email
  end
end

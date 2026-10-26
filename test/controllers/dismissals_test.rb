# frozen_string_literal: true

require "test_helper"

# Closed cards are remembered on the account, so they stay gone on every device.
class DismissalsTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(username: "dismisser", email: "dismisser@example.com", password: "Pw-#{SecureRandom.hex(8)}")
    @joiner = User.create!(username: "newbie", email: "newbie@example.com", password: "Pw-#{SecureRandom.hex(8)}")
    # Joining automatically posts the "just joined" card.
    @join = Announcement.new_members.find_by!(user: @joiner)
    sign_in @user
  end

  test "a closed 'just joined' card stays gone (any device: it's on the account)" do
    get feed_path
    assert_select ".fc-join-card", text: /newbie/

    post dismissals_path, params: { key: "join-#{@join.id}" }
    assert_response :no_content

    get feed_path
    assert_select ".fc-join-card", text: /newbie/, count: 0
  end

  test "keys from the old local storage ('fc:' prefix) work too" do
    post dismissals_path, params: { key: "fc:onboard-feed" }

    assert @user.reload.card_dismissed?("onboard-feed")
  end

  test "rejects junk keys and keeps the list bounded" do
    post dismissals_path, params: { key: "<script>" }
    assert_response :unprocessable_entity

    (User::DISMISSED_CARDS_KEPT + 5).times { |i| @user.dismiss_card!("join-#{i}") }
    assert_equal User::DISMISSED_CARDS_KEPT, @user.reload.dismissed_cards.size
  end
end

# frozen_string_literal: true

require "test_helper"

class PhonePolishTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def make_user(name)
    pass = SecureRandom.base58(16)
    User.create!(username: name, email: "#{name}@example.com", password: pass, password_confirmation: pass)
  end

  test "new brethren show as one card, not one per person" do
    viewer = make_user("viewer_polish")
    %w[ruth_polish naomi_polish boaz_polish].each { |name| make_user(name) }
    sign_in viewer

    get feed_path
    assert_select ".fc-join-card", count: 1
    assert_select ".fc-join-card", text: /just joined us/
  end

  test "the posts list address goes to the feed" do
    sign_in make_user("list_polish")
    get "/posts"
    assert_redirected_to feed_path
  end
end

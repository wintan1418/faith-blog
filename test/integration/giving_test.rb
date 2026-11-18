# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class GivingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    seen = { tour_completed_at: Time.current, welcomed_at: Time.current }
    @member = create_member("give_member", **seen)
    @admin = create_member("give_admin", **seen)
    @admin.update_columns(role: User.roles[:admin])
    @env = ENV.to_h.slice("DONATIONS_PUBLIC", "PAYSTACK_SECRET_KEY")
    ENV.delete("DONATIONS_PUBLIC")
    ENV.delete("PAYSTACK_SECRET_KEY")
  end

  teardown do
    %w[DONATIONS_PUBLIC PAYSTACK_SECRET_KEY].each { |k| @env.key?(k) ? ENV[k] = @env[k] : ENV.delete(k) }
  end

  test "hidden from visitors and members until it's made public" do
    get give_path
    assert_response :not_found
    sign_in @member
    get give_path
    assert_response :not_found
  end

  test "admins see the preview with giving switched off" do
    sign_in @admin
    get give_path
    assert_response :success
    assert_match "only admins can see this page", response.body
    assert_select "button.give-submit[disabled]", text: /Giving opens soon/
  end

  test "everyone can see it once public" do
    ENV["DONATIONS_PUBLIC"] = "1"
    get give_path
    assert_response :success
    assert_no_match "only admins can see", response.body
  end

  test "without a Paystack key nothing is charged" do
    sign_in @admin
    assert_no_difference -> { Donation.count } do
      post give_path, params: { donation: { amount: 5000, currency: "NGN", frequency: "one_time", email: "a@b.co" } }
    end
    assert_redirected_to give_path
  end

  test "with a key it sends the giver to Paystack checkout" do
    ENV["PAYSTACK_SECRET_KEY"] = "sk_test_x"
    sign_in @admin
    Paystack.stub(:request, { "authorization_url" => "https://checkout.paystack.com/abc" }) do
      post give_path, params: { donation: { amount: 5000, currency: "NGN", frequency: "one_time", email: "a@b.co" } }
    end
    assert_redirected_to "https://checkout.paystack.com/abc"
    d = Donation.last
    assert_equal [ 500_000, "NGN", "pending", @admin.id ], [ d.amount_minor, d.currency, d.status, d.user_id ]
  end

  test "amounts under the minimum are refused" do
    ENV["PAYSTACK_SECRET_KEY"] = "sk_test_x"
    sign_in @admin
    post give_path, params: { donation: { amount: 100, currency: "NGN", frequency: "one_time", email: "a@b.co" } }
    assert_response :unprocessable_entity
    assert_match "at least ₦500", response.body
  end

  test "coming back from Paystack confirms the gift" do
    ENV["PAYSTACK_SECRET_KEY"] = "sk_test_x"
    d = Donation.create!(amount: 5000, currency: "NGN", email: "a@b.co", name: "Grace Ade")
    Paystack.stub(:request, { "status" => "success", "amount" => 500_000, "currency" => "NGN" }) do
      get give_thanks_path(reference: d.reference)
    end
    assert_response :success
    assert_match "Thank you, Grace", response.body
    assert d.reload.paid?
  end

  test "the webhook needs Paystack's signature and marks the gift paid once" do
    ENV["PAYSTACK_SECRET_KEY"] = "sk_test_x"
    d = Donation.create!(amount: 10, currency: "USD", email: "a@b.co")
    body = { event: "charge.success", data: { reference: d.reference, amount: 1000, currency: "USD" } }.to_json

    post give_webhook_path, params: body, headers: { "CONTENT_TYPE" => "application/json", "x-paystack-signature" => "bad" }
    assert_response :unauthorized
    assert_not d.reload.paid?

    sig = OpenSSL::HMAC.hexdigest("SHA512", "sk_test_x", body)
    2.times { post give_webhook_path, params: body, headers: { "CONTENT_TYPE" => "application/json", "x-paystack-signature" => sig } }
    assert_response :ok
    assert d.reload.paid?
  end

  test "the webhook ignores a payment smaller than the gift" do
    ENV["PAYSTACK_SECRET_KEY"] = "sk_test_x"
    d = Donation.create!(amount: 10, currency: "USD", email: "a@b.co")
    body = { event: "charge.success", data: { reference: d.reference, amount: 100, currency: "USD" } }.to_json
    sig = OpenSSL::HMAC.hexdigest("SHA512", "sk_test_x", body)
    post give_webhook_path, params: body, headers: { "CONTENT_TYPE" => "application/json", "x-paystack-signature" => sig }
    assert_not d.reload.paid?
  end
end

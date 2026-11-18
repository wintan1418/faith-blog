# frozen_string_literal: true

# Small Paystack client for donations. Needs PAYSTACK_SECRET_KEY (from the
# business account's Paystack dashboard → Settings → API Keys & Webhooks).
module Paystack
  BASE = "https://api.paystack.co"
  Error = Class.new(StandardError)

  module_function

  def secret_key = ENV["PAYSTACK_SECRET_KEY"].presence
  def configured? = secret_key.present?

  # Returns Paystack's checkout URL for the donation.
  def checkout_url(donation, callback_url:)
    body = {
      email: donation.email, amount: donation.amount_minor, currency: donation.currency,
      reference: donation.reference, callback_url: callback_url,
      metadata: { donation_id: donation.id, name: donation.name, anonymous: donation.anonymous }
    }
    if donation.monthly?
      plan = request(:post, "/plan", name: "Brethreign monthly #{donation.display_amount}",
                                     interval: "monthly", amount: donation.amount_minor, currency: donation.currency)
      donation.update!(paystack_plan_code: plan.fetch("plan_code"))
      body[:plan] = donation.paystack_plan_code
    end
    request(:post, "/transaction/initialize", body).fetch("authorization_url")
  end

  # Paystack's record of a payment: { "status" => "success", "amount" => ..., "currency" => ... }
  def verify(reference)
    request(:get, "/transaction/verify/#{ERB::Util.url_encode(reference)}")
  end

  # Webhooks are signed with the secret key (HMAC SHA512 of the raw body).
  def valid_signature?(raw_body, signature)
    return false unless configured? && signature.present?
    expected = OpenSSL::HMAC.hexdigest("SHA512", secret_key, raw_body)
    ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end

  def request(verb, path, body = nil)
    raise Error, "Paystack isn't set up yet" unless configured?
    uri = URI("#{BASE}#{path}")
    req = (verb == :post ? Net::HTTP::Post : Net::HTTP::Get).new(uri)
    req["Authorization"] = "Bearer #{secret_key}"
    req["Content-Type"] = "application/json"
    req.body = body.to_json if body
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) { |http| http.request(req) }
    json = JSON.parse(res.body.presence || "{}")
    raise Error, json["message"].presence || "Paystack error #{res.code}" unless res.is_a?(Net::HTTPSuccess) && json["status"]
    json["data"]
  end
end

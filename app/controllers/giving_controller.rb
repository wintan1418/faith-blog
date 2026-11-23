# frozen_string_literal: true

# /give: the donation page. Only admins can see it until DONATIONS_PUBLIC=1;
# payments start once PAYSTACK_SECRET_KEY is set.
class GivingController < ApplicationController
  skip_forgery_protection only: :webhook
  before_action :ensure_visible, only: %i[show create]
  member_rate_limit to: 10, within: 10.minutes, only: :create, name: "give", per: :ip

  def show
    @donation = Donation.new(currency: params[:currency].presence_in(Donation::CURRENCIES.keys) || "NGN",
                             frequency: "one_time", email: current_user&.email, name: current_user&.display_name)
  end

  def create
    @donation = Donation.new(donation_params.merge(user: current_user))
    @donation.email = current_user.email if @donation.email.blank? && current_user
    unless Donation.payments_open?
      redirect_to give_path, notice: "Giving opens soon. Thank you for your heart to give." and return
    end
    if @donation.save
      redirect_to Paystack.checkout_url(@donation, callback_url: give_thanks_url), allow_other_host: true
    else
      render :show, status: :unprocessable_entity
    end
  rescue Paystack::Error => e
    Rails.logger.error("[Giving] Paystack: #{e.message}")
    @donation.update_column(:status, "failed") if @donation&.persisted?
    redirect_to give_path, alert: "We couldn't reach the payment service. Please try again in a moment."
  end

  # Paystack sends the giver back here with ?reference=...
  def thanks
    @donation = Donation.find_by(reference: params[:reference].to_s)
    return redirect_to(give_path) unless @donation
    confirm(@donation) unless @donation.paid?
  end

  # Paystack → POST /give/webhook (set this URL in the Paystack dashboard).
  def webhook
    raw = request.raw_post
    return head(:unauthorized) unless Paystack.valid_signature?(raw, request.headers["x-paystack-signature"])

    event = JSON.parse(raw)
    if event["event"] == "charge.success"
      data = event["data"] || {}
      donation = Donation.find_by(reference: data["reference"].to_s)
      donation.mark_paid! if donation && amount_matches?(donation, data)
    end
    head :ok
  rescue JSON::ParserError
    head :bad_request
  end

  private

  def ensure_visible
    return if Donation.public? || current_user&.admin? || current_user&.super_admin?
    raise ActionController::RoutingError, "Not Found"
  end

  def donation_params
    params.expect(donation: [ :amount, :currency, :frequency, :email, :name, :anonymous, :message ])
  end

  def confirm(donation)
    data = Paystack.verify(donation.reference)
    if data["status"] == "success" && amount_matches?(donation, data)
      donation.mark_paid!
    elsif %w[failed abandoned reversed].include?(data["status"])
      donation.update!(status: "failed")
    end
  rescue Paystack::Error => e
    Rails.logger.warn("[Giving] verify #{donation.reference}: #{e.message}")
  end

  def amount_matches?(donation, data)
    data["amount"].to_i >= donation.amount_minor && data["currency"].to_s.upcase == donation.currency
  end
end

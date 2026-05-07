# frozen_string_literal: true

class PushSubscriptionsController < ApplicationController
  before_action :authenticate_user!

  # POST /push_subscriptions
  # Body: { endpoint, keys: { p256dh, auth } }
  def create
    endpoint = params.dig(:subscription, :endpoint) || params[:endpoint]
    p256dh   = params.dig(:subscription, :keys, :p256dh) || params.dig(:keys, :p256dh)
    auth     = params.dig(:subscription, :keys, :auth)   || params.dig(:keys, :auth)

    if endpoint.blank? || p256dh.blank? || auth.blank?
      render json: { ok: false, error: "Missing subscription fields." }, status: :unprocessable_entity
      return
    end

    sub = PushSubscription.find_or_initialize_by(endpoint: endpoint)
    sub.user       = current_user
    sub.p256dh_key = p256dh
    sub.auth_key   = auth
    sub.user_agent = request.user_agent.to_s.first(255)
    sub.save!

    render json: { ok: true, id: sub.id }
  end

  # DELETE /push_subscriptions
  # Body: { endpoint }
  def destroy
    endpoint = params[:endpoint] || params.dig(:subscription, :endpoint)
    current_user.push_subscriptions.where(endpoint: endpoint).destroy_all
    render json: { ok: true }
  end

  # GET /push_subscriptions/key — exposes the VAPID public key to the client.
  def key
    render json: { key: WebPushConfig.public_key, configured: WebPushConfig.configured? }
  end
end

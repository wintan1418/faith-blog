# frozen_string_literal: true

class PushSubscriptionsController < ApplicationController
  before_action :authenticate_user!

  # POST /push_subscriptions
  # Body: { endpoint, keys: { p256dh, auth } }
  def create
    endpoint = nested_param(:subscription, :endpoint) || params[:endpoint]
    p256dh   = nested_param(:subscription, :keys, :p256dh) || nested_param(:keys, :p256dh)
    auth     = nested_param(:subscription, :keys, :auth)   || nested_param(:keys, :auth)

    if endpoint.blank? || p256dh.blank? || auth.blank?
      render json: { ok: false, error: "Missing subscription fields." }, status: :unprocessable_entity
      return
    end

    unless PushSubscription.allowed_endpoint?(endpoint)
      render json: { ok: false, error: "That isn't a browser push address." }, status: :unprocessable_entity
      return
    end

    sub = PushSubscription.find_or_initialize_by(endpoint: endpoint)
    # One already saved for someone else only moves to this account when the
    # request carries that browser's own keys too (the same browser, now signed
    # in as someone else), never on the address alone.
    if sub.persisted? && sub.user_id != current_user.id && !same_browser?(sub, p256dh, auth)
      render json: { ok: false, error: "That push address is already in use." }, status: :conflict
      return
    end

    sub.user       = current_user
    sub.p256dh_key = p256dh
    sub.auth_key   = auth
    sub.user_agent = request.user_agent.to_s.first(255)
    if sub.save
      render json: { ok: true, id: sub.id }
    else
      render json: { ok: false, error: sub.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  # DELETE /push_subscriptions
  # Body: { endpoint }
  def destroy
    endpoint = params[:endpoint] || nested_param(:subscription, :endpoint)
    current_user.push_subscriptions.where(endpoint: endpoint).destroy_all
    render json: { ok: true }
  end

  # GET /push_subscriptions/key — exposes the VAPID public key to the client.
  def key
    render json: { key: WebPushConfig.public_key, configured: WebPushConfig.configured? }
  end

  private

  def same_browser?(sub, p256dh, auth)
    ActiveSupport::SecurityUtils.secure_compare(sub.p256dh_key.to_s, p256dh.to_s) &&
      ActiveSupport::SecurityUtils.secure_compare(sub.auth_key.to_s, auth.to_s)
  end
end

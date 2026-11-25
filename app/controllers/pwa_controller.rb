# frozen_string_literal: true

class PwaController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  # The service worker is fetched cross-origin by the browser's worker
  # runtime — Rails' default CSRF rejects it as 422. None of these PWA
  # endpoints have side effects, so skipping the CSRF check is safe.
  skip_forgery_protection only: [ :service_worker, :manifest, :offline ]

  def manifest
    render json: {
      name: "Brethreign",
      short_name: "Brethreign",
      description: "Breathe into the faith community.",
      start_url: "/feed",
      scope: "/",
      display: "standalone",
      orientation: "portrait",
      background_color: "#07110d",
      theme_color: "#07110d",
      # The Brethreign mark on a night tile. ?v= makes installed apps pick up
      # the new icons after the November 2026 rebrand.
      icons: [
        { src: "/icon-192.png?v=2", sizes: "192x192", type: "image/png", purpose: "any" },
        { src: "/icon.png?v=2", sizes: "512x512", type: "image/png", purpose: "any" },
        { src: "/icon-maskable-192.png?v=2", sizes: "192x192", type: "image/png", purpose: "maskable" },
        { src: "/icon-maskable-512.png?v=2", sizes: "512x512", type: "image/png", purpose: "maskable" }
      ],
      shortcuts: [
        { name: "Feed",          short_name: "Feed",       url: "/feed" },
        { name: "Inbox",         short_name: "Inbox",      url: "/inbox" },
        { name: "Reading plans", short_name: "Reading",    url: "/reading_plans" }
      ]
    }
  end

  def offline
    render layout: "application"
  end

  def service_worker
    response.headers["Service-Worker-Allowed"] = "/"
    response.headers["Cache-Control"] = "no-cache"
    render template: "pwa/service_worker", layout: false, formats: [ :js ]
  end
end

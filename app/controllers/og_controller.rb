# frozen_string_literal: true

# Returns an OG (Open Graph / social share) card tinted with the
# requested accent color. Hit at /og.svg?accent=rose so crawlers
# (Twitter, LinkedIn, Slack, Facebook) get the right palette for
# whoever owns the page being shared.
class OgController < ApplicationController
  def show
    slug = params[:accent].to_s
    slug = AccentPalette::DEFAULT unless AccentPalette.valid?(slug)
    @swatch = AccentPalette.for(slug)
    @rgb = AccentPalette.hex_to_rgb(@swatch[:accent])

    expires_in 1.hour, public: true
    render template: "og/show", layout: false, formats: [ :svg ]
  end
end

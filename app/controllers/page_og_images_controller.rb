# frozen_string_literal: true

# /og/pages/<handle>.jpg?v=<version>: a page's link-preview card (PageOgCard)
# for crawlers. Active pages only; the house card if drawing fails.
class PageOgImagesController < ApplicationController
  def show
    page = Page.listed.find_by_handle!(params[:handle])
    data = PageOgCard.new(page).jpeg
    expires_in 1.day, public: true
    request.session_options[:skip] = true
    send_data data, type: "image/jpeg", disposition: "inline", filename: "page-#{page.id}.jpg"
  rescue ActiveRecord::RecordNotFound
    head :not_found
  rescue StandardError => e
    Rails.logger.warn("[og] page card failed for #{params[:handle]}: #{e.class}: #{e.message}")
    redirect_to "/og/#{AccentPalette::DEFAULT}.jpg"
  end
end

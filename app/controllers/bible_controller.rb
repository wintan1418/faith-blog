# frozen_string_literal: true

class BibleController < ApplicationController
  before_action :authenticate_user!

  def search
    query = params[:query].to_s.strip
    if query.length < 4
      render json: { ok: false, error: "Type a few more words." }, status: :unprocessable_entity
      return
    end
    if query.length > 200
      render json: { ok: false, error: "Query too long." }, status: :unprocessable_entity
      return
    end

    result = Ai::Bible::Searcher.call(query: query)
    render json: {
      ok: true,
      verses: result.verses.map { |v| { reference: v.reference, reason: v.reason } }
    }
  rescue Ai::Bible::Searcher::ParseError, Ai::Moderation::Client::Error => e
    Rails.logger.warn("[BibleSearch] #{e.class}: #{e.message}")
    render json: { ok: false, error: "Couldn't reach the search right now." }, status: :bad_gateway
  end
end

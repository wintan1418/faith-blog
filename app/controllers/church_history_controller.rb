# frozen_string_literal: true

class ChurchHistoryController < ApplicationController
  before_action :authenticate_user!

  ERA_ORDER = %w[apostolic patristic medieval reformation modern revivalists].freeze

  def index
    @figures_by_era = ChurchHistoryFigure.ordered.group_by(&:era)
    @era            = params[:era].to_s.presence || "apostolic"
    @era            = "apostolic" unless ERA_ORDER.include?(@era)
    @chronicles     = ChurchHistoryEra.all.index_by(&:slug)
  end

  # GET /history/era/:era/chronicle — lazy AI generation
  def chronicle
    era = params[:era].to_s
    return render(json: { ok: false, error: "Bad era." }, status: :bad_request) unless ERA_ORDER.include?(era)

    row = ChurchHistoryEra.find_or_initialize_by(slug: era)
    if row.summary.blank?
      row.summary = Ai::Christian::EraChronicle.call(era: era)
      row.generated_at = Time.current
      row.save!
    end
    render json: { ok: true, chronicle: row.summary }
  rescue Ai::Christian::EraChronicle::ParseError, Ai::Moderation::Client::Error => e
    Rails.logger.warn("[EraChronicle] #{e.class}: #{e.message}")
    render json: { ok: false, error: "Couldn't fetch the chronicle right now." }, status: :bad_gateway
  end

  # Returns the figure's bio JSON. Generates and caches on first request.
  def figure
    figure = ChurchHistoryFigure.find_by!(slug: params[:slug])
    bio    = ensure_bio(figure)
    render json: {
      ok: true,
      name: figure.name,
      era_label: ChurchHistoryFigure::ERA_LABELS[figure.era],
      years: figure.years,
      claim: figure.claim,
      featured_quote: figure.featured_quote.presence || bio[:quote],
      bio: figure.bio
    }
  rescue ActiveRecord::RecordNotFound
    render json: { ok: false, error: "Not found." }, status: :not_found
  rescue Ai::Christian::FigureBio::ParseError, Ai::Moderation::Client::Error => e
    Rails.logger.warn("[FigureBio] #{e.class}: #{e.message}")
    render json: { ok: false, error: "Couldn't fetch a bio right now." }, status: :bad_gateway
  end

  private

  def ensure_bio(figure)
    return { bio: figure.bio, quote: figure.featured_quote } if figure.bio.present?

    result = Ai::Christian::FigureBio.call(figure: figure)
    figure.update!(
      bio: result[:bio],
      featured_quote: figure.featured_quote.presence || result[:quote],
      bio_generated_at: Time.current
    )
    result
  end
end

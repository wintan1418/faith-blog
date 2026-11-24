# frozen_string_literal: true

# /sitemap.xml is a sitemap index: /sitemaps/pages.xml (breaths, rooms,
# resources, blog) and /sitemaps/scripture-N.xml (every scripture page we
# want found: all 1,189 chapters, the most-searched verses, verses members
# quote, and every page with a written insight). Split so no file nears the
# 50,000-URL limit.
class SitemapsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  POSTS_LIMIT = 5_000
  SCRIPTURE_PER_FILE = 10_000

  def show
    @scripture_files = (scripture_references.size.to_f / SCRIPTURE_PER_FILE).ceil.clamp(1, 50)
    @scripture_lastmod = ScriptureInsight.maximum(:generated_at)
    expires_in 1.hour, public: true
    render formats: [ :xml ]
  end

  def pages
    @posts = Post.published.where(room_id: [ nil, *Room.public_rooms.select(:id) ])
                 .order(published_at: :desc).limit(POSTS_LIMIT).select(:id, :slug, :updated_at)
    @rooms = Room.public_rooms.select(:id, :slug, :updated_at)
    @resources = Resource.approved.select(:id, :slug, :updated_at)

    expires_in 1.hour, public: true
    render formats: [ :xml ]
  end

  def scripture
    page = params[:page].to_i
    @references = scripture_references.drop((page - 1) * SCRIPTURE_PER_FILE).first(SCRIPTURE_PER_FILE)
    raise ActiveRecord::RecordNotFound if page < 1 || (page > 1 && @references.empty?)

    @generated = ScriptureInsight.pluck(:slug, :generated_at).to_h
    expires_in 1.hour, public: true
    render formats: [ :xml ]
  end

  # "1 John 3:16" -> "1-john-3-16" (the canonical scripture page slug).
  def self.scripture_slug(reference)
    Scripture::Reference.parse(reference)&.slug ||
      reference.to_s.downcase.gsub(/[^a-z0-9]+/, "-").delete_prefix("-").delete_suffix("-")
  end

  private

  def scripture_references
    @scripture_references ||= Scripture::Catalog.sitemap.sort
  end
end

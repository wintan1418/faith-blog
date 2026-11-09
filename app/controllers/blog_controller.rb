# frozen_string_literal: true

# The Brethreign blog: guides, tutorials and news, readable by anyone.
class BlogController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  def index
    @category = BlogArticle::CATEGORIES.find { |name| name.casecmp?(params[:category].to_s) }
    @featured = BlogArticle.featured unless @category
    @articles = @category ? BlogArticle.in_category(@category) : BlogArticle.all.reject { |a| a == @featured }
    expires_in 10.minutes, public: true unless user_signed_in?
  end

  def show
    @article = BlogArticle.find(params[:slug])
    expires_in 10.minutes, public: true unless user_signed_in?
  end

  # Development only (see routes): a 1200×630 page for the cover art.
  def cover
    @article = BlogArticle.find(params[:slug])
    render layout: false
  end

  def feed
    @articles = BlogArticle.all
    render formats: [ :rss ], content_type: "application/rss+xml"
  end
end

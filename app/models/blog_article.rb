# frozen_string_literal: true

require "kramdown"
require "kramdown-parser-gfm"

# A blog article: a Markdown file in app/content/blog with YAML front matter.
# Publishing an article means adding its file (and its pictures under
# public/blog) and deploying. Articles are read once per boot in production.
class BlogArticle
  DIR = Rails.root.join("app/content/blog")
  CATEGORIES = %w[Professional Guides Community Safety News].freeze
  WORDS_PER_MINUTE = 220

  # What article HTML may contain. The files are ours, but a mistake in one
  # shouldn't be able to inject a script.
  ALLOWED_TAGS = %w[h2 h3 h4 p br hr ul ol li strong b em i a code pre blockquote figure figcaption img aside div span
                    table thead tbody tr th td].freeze
  ALLOWED_ATTRIBUTES = %w[href src alt class id title loading decoding width height].freeze

  attr_reader :slug, :title, :description, :category, :order, :date, :cover_shots, :cover_title, :featured, :body

  def self.all
    return load_all if Rails.env.development?

    @all ||= load_all
  end

  def self.find(slug) = all.find { |article| article.slug == slug.to_s } || raise(ActiveRecord::RecordNotFound)
  def self.featured = all.find(&:featured) || all.first
  def self.in_category(name) = all.select { |article| article.category == name }

  def self.load_all
    Dir[DIR.join("*.md")].map { |path| new(path) }.sort_by { |article| [ article.order, article.title ] }
  end

  def self.reset! = @all = nil

  def initialize(path)
    @slug = File.basename(path, ".md")
    raw = File.read(path)
    meta, @body = split_front_matter(raw)
    @title = meta.fetch("title")
    @description = meta["description"].to_s
    @category = CATEGORIES.include?(meta["category"]) ? meta["category"] : "Guides"
    @order = meta["order"].to_i
    @date = meta["date"].present? ? Date.parse(meta["date"].to_s) : Date.new(2026, 11, 9)
    @cover_shots = Array(meta["cover"]).map(&:to_s)
    @cover_title = meta["cover_title"].presence || @title
    @featured = meta["featured"] == true
  end

  def to_param = slug
  def ==(other) = other.is_a?(BlogArticle) && other.slug == slug
  alias eql? ==
  def hash = slug.hash
  def cover_path = "/blog/covers/#{slug}.jpg"
  def minutes = [ (body.scan(/[[:alnum:]’']+/).size / WORDS_PER_MINUTE.to_f).ceil, 1 ].max

  def html
    @html ||= begin
      rendered = Kramdown::Document.new(body, input: "GFM", hard_wrap: false, auto_ids: true,
                                              syntax_highlighter: nil).to_html
      rendered = rendered.gsub("<img ", '<img loading="lazy" decoding="async" ')
      Rails::HTML5::SafeListSanitizer.new.sanitize(rendered, tags: ALLOWED_TAGS, attributes: ALLOWED_ATTRIBUTES)
    end
  end

  # The ## headings, for the "In this article" list.
  def headings
    @headings ||= html.scan(%r{<h2 id="([^"]+)">(.*?)</h2>}m).map do |id, text|
      [ id, ActionController::Base.helpers.strip_tags(text) ]
    end
  end

  def related(limit = 3)
    others = self.class.all.reject { |article| article.slug == slug }
    (others.select { |article| article.category == category } + others).uniq.first(limit)
  end

  private

  def split_front_matter(raw)
    match = raw.match(/\A---\s*\n(.*?)\n---\s*\n/m)
    raise ArgumentError, "#{slug}: missing front matter" unless match

    [ YAML.safe_load(match[1], permitted_classes: [ Date ]) || {}, match.post_match ]
  end
end

# frozen_string_literal: true

require "test_helper"

class BlogTest < ActionDispatch::IntegrationTest
  test "every article file is valid and its pictures exist" do
    articles = BlogArticle.load_all
    assert_operator articles.size, :>=, 20
    assert_equal articles.map(&:slug).uniq.size, articles.size
    articles.each do |article|
      assert_includes BlogArticle::CATEGORIES, article.category, article.slug
      assert article.description.length.between?(40, 160), "#{article.slug}: description length"
      assert File.exist?(Rails.public_path.join(article.cover_path.delete_prefix("/"))), "#{article.slug}: cover missing"
      article.html.scan(%r{src="(/blog/[^"]+)"}).flatten.each do |src|
        assert File.exist?(Rails.public_path.join(src.delete_prefix("/"))), "#{article.slug}: #{src} missing"
      end
      assert_no_match(/<script/i, article.html)
    end
  end

  test "the blog front page lists articles for anyone, signed in or not" do
    get blog_path
    assert_response :success
    assert_select "h1", text: /Learn your way around/
    assert_select ".bl-card--wide .bl-card-title", text: BlogArticle.featured.title
    assert_select ".bl-grid .bl-card", count: BlogArticle.all.size - 1
    assert_select ".bl-series-list li", count: BlogArticle.in_category("Professional").size - 1
  end

  test "a category shows only its articles" do
    get blog_path(category: "professional")
    assert_select ".bl-chip.is-on", text: /Professional/
    assert_select ".bl-card", count: BlogArticle.in_category("Professional").size
  end

  test "an article page has its title, pictures, link preview and structured data" do
    article = BlogArticle.find("import-your-linkedin-profile")
    get blog_article_path(article.slug)
    assert_response :success
    assert_select "h1.bl-title", text: article.title
    assert_select ".bl-body figure.bl-shot img", minimum: 2
    assert_select "meta[property='og:image'][content$=?]", article.cover_path
    assert_select "meta[name=description][content=?]", article.description
    assert_select "script[type='application/ld+json']", text: /"@type":"Article"/
    assert_select ".bl-toc a", minimum: 3
  end

  test "an unknown article is a 404" do
    get "/blog/no-such-article"
    assert_response :not_found
  end

  test "the RSS feed and sitemap include the articles" do
    get blog_feed_path
    assert_response :success
    assert_match "<title>Brethreign Blog</title>", response.body
    assert_match blog_article_url("welcome-to-brethreign"), response.body

    get "/sitemap.xml"
    assert_match blog_article_url("introducing-brethreign-professional"), response.body
  end
end

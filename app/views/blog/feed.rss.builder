xml.instruct! :xml, version: "1.0"
xml.rss version: "2.0", "xmlns:atom" => "http://www.w3.org/2005/Atom" do
  xml.channel do
    xml.title "Brethreign Blog"
    xml.link blog_url
    xml.description "Guides, tutorials and news from Brethreign."
    xml.language "en"
    xml.tag! "atom:link", href: blog_feed_url, rel: "self", type: "application/rss+xml"
    @articles.sort_by { |a| [ -a.date.to_time.to_i, a.order ] }.each do |article|
      xml.item do
        xml.title article.title
        xml.link blog_article_url(article.slug)
        xml.guid blog_article_url(article.slug)
        xml.pubDate article.date.to_time.rfc2822
        xml.category article.category
        xml.description article.description
      end
    end
  end
end

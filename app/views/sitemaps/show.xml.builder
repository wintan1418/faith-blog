xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  [ [ root_url, "daily", 1.0 ], [ about_url, "monthly", 0.6 ], [ rooms_url, "daily", 0.7 ], [ resources_root_url, "weekly", 0.6 ] ].each do |loc, freq, priority|
    xml.url { xml.loc loc; xml.changefreq freq; xml.priority priority }
  end
  xml.url { xml.loc blog_url; xml.changefreq "weekly"; xml.priority 0.8 }
  BlogArticle.all.each do |article|
    xml.url { xml.loc blog_article_url(article.slug); xml.lastmod article.date.iso8601; xml.changefreq "monthly"; xml.priority 0.7 }
  end
  @rooms.each do |room|
    xml.url { xml.loc room_url(room); xml.lastmod room.updated_at.to_date.iso8601; xml.changefreq "daily" }
  end
  @posts.each do |post|
    xml.url { xml.loc post_url(post); xml.lastmod post.updated_at.to_date.iso8601 }
  end
  @resources.each do |resource|
    xml.url { xml.loc resources_item_url(resource); xml.lastmod resource.updated_at.to_date.iso8601 }
  end
  @scripture_slugs.each do |slug|
    xml.url { xml.loc scripture_page_url(slug: slug); xml.changefreq "weekly"; xml.priority 0.5 }
  end
end

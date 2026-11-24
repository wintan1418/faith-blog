xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.sitemapindex xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  xml.sitemap { xml.loc pages_sitemap_url }
  (1..@scripture_files).each do |page|
    xml.sitemap do
      xml.loc scripture_sitemap_url(page: page)
      xml.lastmod @scripture_lastmod.to_date.iso8601 if @scripture_lastmod
    end
  end
end

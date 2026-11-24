xml.instruct! :xml, version: "1.0", encoding: "UTF-8"
xml.urlset xmlns: "http://www.sitemaps.org/schemas/sitemap/0.9" do
  xml.url { xml.loc scripture_index_url; xml.changefreq "monthly"; xml.priority 0.6 }
  @references.each do |reference|
    xml.url do
      xml.loc scripture_page_url(slug: reference.slug)
      generated = @generated[reference.slug]
      xml.lastmod generated.to_date.iso8601 if generated
    end
  end
end

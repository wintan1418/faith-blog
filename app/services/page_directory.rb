# frozen_string_literal: true

# Finding pages: the /pages directory (search, category, near you,
# suggested) and the Pages tab in site search. Only active pages are ever
# listed; nothing here shows who runs a page.
class PageDirectory
  NEAR_KM = 80

  def initialize(viewer)
    @viewer = viewer
  end

  def base = Page.listed.includes(:city, logo_attachment: :blob)

  # Name, handle, tagline, category, place and about, best first: exact
  # handle, then name starts with the words, then full-text rank, then size.
  def search(query, category: nil)
    text = query.to_s.squish.delete_prefix("@").first(100)
    scope = base
    scope = scope.where(category: category) if category.present? && Page.categories.key?(category)
    return scope.order(Arel.sql("pages.verified_at IS NULL"), followers_count: :desc, name: :asc) if text.blank?

    like = "%#{Page.sanitize_sql_like(text)}%"
    tsq = Page.sanitize_sql_array([ "websearch_to_tsquery('public.brethreign_search', ?)", text ])
    rank = Page.sanitize_sql_array([
      "(CASE WHEN lower(pages.handle) = lower(:t) THEN 0 WHEN pages.name ILIKE :prefix THEN 1 ELSE 2 END), " \
      "ts_rank_cd(pages.searchable, #{tsq}) DESC, pages.followers_count DESC, pages.id",
      t: text, prefix: "#{Page.sanitize_sql_like(text)}%"
    ])
    scope.where("pages.searchable @@ #{tsq} OR pages.name ILIKE :like OR pages.handle ILIKE :like", like: like)
         .order(Arel.sql(rank))
  end

  def city = @viewer&.profile&.city

  # Pages in or around the viewer's city (by city centre; no one's position).
  def near(limit: 6)
    return Page.none unless city

    base.joins(:city)
        .where("#{City::DISTANCE_SQL} <= :km", lat: city.lat.to_f, lng: city.lng.to_f, km: NEAR_KM)
        .order(Arel.sql(City.sanitize_sql_array([ "#{City::DISTANCE_SQL}", { lat: city.lat.to_f, lng: city.lng.to_f } ])),
               followers_count: :desc)
        .limit(limit)
  end

  # A few pages worth following: not followed or run by the viewer, verified
  # and well-followed first, from their country when we know it.
  def suggested(limit: 6)
    scope = base
    if @viewer
      scope = scope.where.not(id: PageFollow.where(user_id: @viewer.id).select(:page_id))
                   .where.not(id: PageMembership.where(user_id: @viewer.id).select(:page_id))
    end
    country = city&.country_code
    order = [ Arel.sql("pages.verified_at IS NULL") ]
    if country
      order << Arel.sql(Page.sanitize_sql_array([ "(SELECT cities.country_code FROM cities WHERE cities.id = pages.city_id) IS DISTINCT FROM ?", country ]))
    end
    scope.order(*order, followers_count: :desc, created_at: :desc).limit(limit)
  end
end

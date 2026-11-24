# frozen_string_literal: true

module SiteSearch
  # The non-breath tabs: people, rooms, Bible and resources. Each takes the
  # same Visibility as breaths, so a tab never shows what browsing wouldn't.
  class Sections
    BibleVerseHit = Data.define(:reference, :text)

    def initialize(query, visibility)
      @query = query
      @visibility = visibility
    end

    def conn = ActiveRecord::Base.connection

    # Members only (as before: no profile probing while signed out). Exact
    # username first, then usernames starting with the words, then the rest;
    # bio and the like only match on public profiles (User.member_search).
    def people(limit: 20, offset: 0)
      return User.none if @visibility.guest?

      words = @query.plain_text.presence || @query.text
      return User.none if words.blank?

      handle = words.delete_prefix("@").first(60)
      quoted = conn.quote(handle.downcase)
      @visibility.users_scope.member_search(handle)
                 .includes(profile: { avatar_attachment: :blob })
                 .order(Arel.sql("CASE WHEN lower(users.username) = #{quoted} THEN 0 " \
                                 "WHEN lower(users.username) LIKE #{conn.quote("#{User.sanitize_sql_like(handle.downcase)}%")} THEN 1 ELSE 2 END"),
                        Arel.sql("length(users.username)"), :username)
                 .limit(limit).offset(offset)
    end

    # Instant search: usernames only, through the trigram index.
    def people_quick(limit: 3)
      return [] if @visibility.guest?

      handle = (@query.plain_text.presence || @query.text).delete_prefix("@").first(60)
      return [] if handle.length < 2

      like = "%#{User.sanitize_sql_like(handle)}%"
      @visibility.users_scope.where("users.username ILIKE ?", like)
                 .includes(profile: { avatar_attachment: :blob })
                 .order(Arel.sql("CASE WHEN users.username ILIKE #{conn.quote("#{User.sanitize_sql_like(handle)}%")} THEN 0 ELSE 1 END"),
                        Arel.sql("length(users.username)"))
                 .limit(limit).to_a
    end

    # Rooms are few: match name or description, accent- and style-insensitively.
    def rooms(limit: 12)
      words = @query.plain_text
      return Room.none if words.blank?

      key = { key: words.first(100) }
      @visibility.rooms_scope
                 .where("public.search_key(rooms.name) LIKE '%' || public.search_key(:key) || '%' " \
                        "OR public.search_key(coalesce(rooms.description, '')) LIKE '%' || public.search_key(:key) || '%' " \
                        "OR word_similarity(public.search_key(:key), public.search_key(rooms.name)) >= 0.5", key)
                 .order(Arel.sql(Room.sanitize_sql_array([ "CASE WHEN public.search_key(rooms.name) = public.search_key(:key) THEN 0 " \
                                                           "WHEN public.search_key(rooms.name) LIKE public.search_key(:key) || '%' THEN 1 ELSE 2 END", key ])),
                        posts_count: :desc)
                 .limit(limit)
    end

    # "john 3 16", "Ps 23", "1 cor 13:4-7" → the scripture page.
    def reference
      return @reference if defined?(@reference)

      @reference = Scripture::Reference.parse(@query.text.delete('"'))
    end

    # Verses (KJV) containing the words, best first.
    def verses(limit: 20)
      words = @query.plain_text
      return [] if words.blank? || !ScriptureVerse.table_exists?

      words = words.first(200)
      rank = ScriptureVerse.sanitize_sql_array([ "ts_rank(to_tsvector('english'::regconfig, text), plainto_tsquery('english', ?)) DESC", words ])
      ScriptureVerse.where(translation: ScriptureVerse::PRIMARY)
                    .where("to_tsvector('english'::regconfig, text) @@ plainto_tsquery('english', ?)", words)
                    .order(Arel.sql(rank), :book, :chapter, :verse)
                    .limit(limit)
                    .filter_map do |verse|
                      book = Scripture::Canon[verse.book]
                      ref = book && Scripture::Reference.build(book, verse.chapter, verse.verse)
                      ref && BibleVerseHit.new(reference: ref, text: verse.text)
                    end
    end

    def resources(limit: 20)
      words = @query.plain_text
      return Resource.none if words.blank?

      Resource.approved.search(words.first(200)).includes(:resource_category).limit(limit)
    end
  end
end

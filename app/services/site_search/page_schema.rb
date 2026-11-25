# frozen_string_literal: true

module SiteSearch
  # The database side of Pages in search (installed after SiteSearch::Schema,
  # whose post triggers it replaces with page-aware ones):
  #
  # * every page has a weighted vector: name A, handle and tagline B,
  #   category, city, location and tradition C, about D
  # * a post written as a page is indexed under the page's name, never the
  #   name of the member who wrote it (the page is who said it)
  #
  # Idempotent; runs from its migration and after every schema load
  # (config/initializers/site_search_schema.rb).
  module PageSchema
    SQL = <<~SQL
      CREATE OR REPLACE FUNCTION public.page_search_document(p_name text, p_handle text, p_tagline text, p_category integer,
                                                             p_city_id bigint, p_location text, p_tradition text, p_about text)
        RETURNS tsvector LANGUAGE sql STABLE AS $$
          SELECT setweight(to_tsvector('public.brethreign_search'::regconfig, normalize(coalesce(p_name, ''), NFKC)), 'A')
              || setweight(to_tsvector('public.brethreign_search'::regconfig,
                             normalize(coalesce(p_handle, '') || ' ' || coalesce(p_tagline, ''), NFKC)), 'B')
              || setweight(to_tsvector('public.brethreign_search'::regconfig, normalize(
                             (CASE p_category WHEN 0 THEN 'church' WHEN 1 THEN 'ministry' WHEN 2 THEN 'fellowship campus'
                                              WHEN 3 THEN 'business' WHEN 4 THEN 'school' WHEN 5 THEN 'nonprofit ngo charity'
                                              WHEN 6 THEN 'community' WHEN 7 THEN 'media' ELSE '' END) || ' ' ||
                             coalesce((SELECT name || ' ' || coalesce(admin1_name, '') || ' ' || country_name FROM cities WHERE id = p_city_id), '') || ' ' ||
                             coalesce(p_location, '') || ' ' || coalesce(p_tradition, ''), NFKC)), 'C')
              || setweight(to_tsvector('public.brethreign_search'::regconfig, normalize(left(coalesce(p_about, ''), 20000), NFKC)), 'D')
        $$;

      CREATE OR REPLACE FUNCTION public.pages_search_trigger() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        NEW.searchable := public.page_search_document(NEW.name, NEW.handle, NEW.tagline, NEW.category,
                                                      NEW.city_id, NEW.location, NEW.tradition, NEW.about);
        RETURN NEW;
      END
      $$;

      -- A breath's vector; a page post carries the page's name as its author.
      CREATE OR REPLACE FUNCTION public.post_search_document_v2(p_id bigint, p_title text, p_anonymous boolean, p_user_id bigint,
                                                                p_room_id bigint, p_page_id bigint)
        RETURNS tsvector LANGUAGE sql STABLE AS $$
          SELECT public.search_document(
            p_title,
            public.search_html_text((SELECT body FROM action_text_rich_texts
                                      WHERE record_type = 'Post' AND record_id = p_id AND name = 'content')),
            CASE WHEN p_anonymous THEN NULL
                 WHEN p_page_id IS NOT NULL THEN (SELECT name || ' ' || handle FROM pages WHERE id = p_page_id)
                 ELSE (SELECT username FROM users WHERE id = p_user_id) END,
            (SELECT name FROM rooms WHERE id = p_room_id))
        $$;

      CREATE OR REPLACE FUNCTION public.posts_search_trigger() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        NEW.searchable := public.post_search_document_v2(NEW.id, NEW.title, NEW.anonymous, NEW.user_id, NEW.room_id, NEW.page_id);
        NEW.search_title := public.search_key(NEW.title);
        RETURN NEW;
      END
      $$;

      CREATE OR REPLACE FUNCTION public.rich_texts_search_trigger() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE
        r action_text_rich_texts%ROWTYPE;
      BEGIN
        IF TG_OP = 'DELETE' THEN r := OLD; ELSE r := NEW; END IF;
        IF r.name = 'content' AND r.record_type = 'Post' THEN
          UPDATE posts p SET searchable = public.post_search_document_v2(p.id, p.title, p.anonymous, p.user_id, p.room_id, p.page_id)
           WHERE p.id = r.record_id;
        ELSIF r.name = 'content' AND r.record_type = 'Comment' THEN
          UPDATE comments c SET searchable = public.comment_search_document(c.id, c.content)
           WHERE c.id = r.record_id;
        END IF;
        RETURN NULL;
      END
      $$;

      CREATE OR REPLACE FUNCTION public.users_search_trigger() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        UPDATE posts p SET searchable = public.post_search_document_v2(p.id, p.title, p.anonymous, p.user_id, p.room_id, p.page_id)
         WHERE p.user_id = NEW.id AND NOT p.anonymous AND p.page_id IS NULL;
        RETURN NULL;
      END
      $$;

      CREATE OR REPLACE FUNCTION public.rooms_search_trigger() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        UPDATE posts p SET searchable = public.post_search_document_v2(p.id, p.title, p.anonymous, p.user_id, p.room_id, p.page_id)
         WHERE p.room_id = NEW.id;
        RETURN NULL;
      END
      $$;

      CREATE OR REPLACE FUNCTION public.page_posts_search_trigger() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        UPDATE posts p SET searchable = public.post_search_document_v2(p.id, p.title, p.anonymous, p.user_id, p.room_id, p.page_id)
         WHERE p.page_id = NEW.id;
        RETURN NULL;
      END
      $$;

      DROP TRIGGER IF EXISTS posts_search_refresh ON posts;
      CREATE TRIGGER posts_search_refresh BEFORE INSERT OR UPDATE OF title, anonymous, user_id, room_id, page_id ON posts
        FOR EACH ROW EXECUTE FUNCTION public.posts_search_trigger();

      DROP TRIGGER IF EXISTS pages_search_refresh ON pages;
      CREATE TRIGGER pages_search_refresh BEFORE INSERT OR UPDATE OF name, handle, tagline, category, city_id, location, tradition, about ON pages
        FOR EACH ROW EXECUTE FUNCTION public.pages_search_trigger();

      DROP TRIGGER IF EXISTS pages_posts_search_refresh ON pages;
      CREATE TRIGGER pages_posts_search_refresh AFTER UPDATE OF name, handle ON pages
        FOR EACH ROW WHEN (OLD.name IS DISTINCT FROM NEW.name OR OLD.handle IS DISTINCT FROM NEW.handle)
        EXECUTE FUNCTION public.page_posts_search_trigger();
    SQL

    # Back to SiteSearch::Schema's own post triggers.
    DROP_SQL = <<~SQL
      DROP TRIGGER IF EXISTS pages_posts_search_refresh ON pages;
      DROP TRIGGER IF EXISTS pages_search_refresh ON pages;
      DROP FUNCTION IF EXISTS public.page_posts_search_trigger();
      DROP FUNCTION IF EXISTS public.pages_search_trigger();
      DROP FUNCTION IF EXISTS public.page_search_document(text, text, text, integer, bigint, text, text, text);
    SQL

    module_function

    def applicable?(connection)
      Schema.applicable?(connection) && connection.table_exists?(:pages) &&
        connection.column_exists?(:pages, :searchable) && connection.column_exists?(:posts, :page_id)
    end

    def install!(connection = ActiveRecord::Base.connection)
      return false unless applicable?(connection)

      connection.execute(SQL)
      true
    end

    def drop!(connection = ActiveRecord::Base.connection)
      connection.execute(DROP_SQL)
      Schema.install!(connection) # restores the original post triggers
      connection.execute("DROP FUNCTION IF EXISTS public.post_search_document_v2(bigint, text, boolean, bigint, bigint, bigint)")
    end
  end
end

# frozen_string_literal: true

module SiteSearch
  # The database side of search: a text search configuration, a few SQL
  # functions and the triggers that keep every search vector up to date.
  #
  # Nothing in Ruby writes a vector. Postgres rebuilds a breath's vector when
  # its title, author, room or text changes (and a reply's when its text
  # changes), so the index can't drift from what's on the page.
  #
  # Vectors are built from NFKC-normalized text: titles written in "fancy"
  # Unicode letters (𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿) are indexed as plain letters, and the
  # unaccent dictionary makes "café" and "cafe" the same word.
  #
  # schema.rb can't hold functions or triggers, so `install!` runs from the
  # migration and again after every schema load (see
  # config/initializers/site_search_schema.rb). It is idempotent.
  module Schema
    CONFIG = "public.brethreign_search"

    # Weights: title A, text B, author username C (never for anonymous
    # breaths), room name D.
    SQL = <<~SQL
      CREATE EXTENSION IF NOT EXISTS unaccent;

      DO $$
      BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_ts_config WHERE cfgname = 'brethreign_search') THEN
          CREATE TEXT SEARCH CONFIGURATION public.brethreign_search (COPY = pg_catalog.english);
          ALTER TEXT SEARCH CONFIGURATION public.brethreign_search
            ALTER MAPPING FOR hword, hword_part, word WITH public.unaccent, english_stem;
        END IF;
      END
      $$;

      -- Lower-case, accent-free, NFKC-normalized text: for trigram matching
      -- and exact-title comparison. IMMUTABLE so it can back an index.
      CREATE OR REPLACE FUNCTION public.search_fold(text) RETURNS text
        LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
        RETURN lower(public.unaccent('public.unaccent'::regdictionary, normalize($1, NFKC)));

      -- Folded text with punctuation squeezed out: how titles are compared
      -- ("Who Is a Teenager? (1)" and "who is a teenager 1" are the same key).
      CREATE OR REPLACE FUNCTION public.search_key(text) RETURNS text
        LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
        RETURN btrim(regexp_replace(public.search_fold($1), '[^[:alnum:]]+', ' ', 'g'));

      -- Plain text out of Action Text HTML (tags dropped, common entities decoded).
      CREATE OR REPLACE FUNCTION public.search_html_text(html text) RETURNS text
        LANGUAGE sql IMMUTABLE PARALLEL SAFE
        RETURN replace(replace(replace(replace(replace(replace(
                 regexp_replace(left(coalesce(html, ''), 300000), '<[^>]*>', ' ', 'g'),
                 '&nbsp;', ' '), '&lt;', '<'), '&gt;', '>'), '&quot;', '"'), '&#39;', ''''), '&amp;', '&');

      CREATE OR REPLACE FUNCTION public.search_document(title text, body text, author text, room text) RETURNS tsvector
        LANGUAGE sql IMMUTABLE PARALLEL SAFE
        RETURN setweight(to_tsvector('public.brethreign_search'::regconfig, normalize(coalesce(title, ''), NFKC)), 'A')
            || setweight(to_tsvector('public.brethreign_search'::regconfig, normalize(left(coalesce(body, ''), 100000), NFKC)), 'B')
            || setweight(to_tsvector('public.brethreign_search'::regconfig, normalize(coalesce(author, ''), NFKC)), 'C')
            || setweight(to_tsvector('public.brethreign_search'::regconfig, normalize(coalesce(room, ''), NFKC)), 'D');

      -- A breath's vector from its row values plus its text, author and room.
      -- Anonymous breaths never carry their author's name.
      CREATE OR REPLACE FUNCTION public.post_search_document(p_id bigint, p_title text, p_anonymous boolean, p_user_id bigint, p_room_id bigint)
        RETURNS tsvector LANGUAGE sql STABLE AS $$
          SELECT public.search_document(
            p_title,
            public.search_html_text((SELECT body FROM action_text_rich_texts
                                      WHERE record_type = 'Post' AND record_id = p_id AND name = 'content')),
            CASE WHEN p_anonymous THEN NULL ELSE (SELECT username FROM users WHERE id = p_user_id) END,
            (SELECT name FROM rooms WHERE id = p_room_id))
        $$;

      CREATE OR REPLACE FUNCTION public.comment_search_document(c_id bigint, c_content text)
        RETURNS tsvector LANGUAGE sql STABLE AS $$
          SELECT to_tsvector('public.brethreign_search'::regconfig, normalize(left(coalesce(
            public.search_html_text((SELECT body FROM action_text_rich_texts
                                      WHERE record_type = 'Comment' AND record_id = c_id AND name = 'content')),
            c_content, ''), 20000), NFKC))
        $$;

      CREATE OR REPLACE FUNCTION public.posts_search_trigger() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        NEW.searchable := public.post_search_document(NEW.id, NEW.title, NEW.anonymous, NEW.user_id, NEW.room_id);
        NEW.search_title := public.search_key(NEW.title);
        RETURN NEW;
      END
      $$;

      CREATE OR REPLACE FUNCTION public.comments_search_trigger() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        NEW.searchable := public.comment_search_document(NEW.id, NEW.content);
        RETURN NEW;
      END
      $$;

      -- Action Text saves a record's text after the record itself.
      CREATE OR REPLACE FUNCTION public.rich_texts_search_trigger() RETURNS trigger LANGUAGE plpgsql AS $$
      DECLARE
        r action_text_rich_texts%ROWTYPE;
      BEGIN
        IF TG_OP = 'DELETE' THEN r := OLD; ELSE r := NEW; END IF;
        IF r.name = 'content' AND r.record_type = 'Post' THEN
          UPDATE posts p SET searchable = public.post_search_document(p.id, p.title, p.anonymous, p.user_id, p.room_id)
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
        UPDATE posts p SET searchable = public.post_search_document(p.id, p.title, p.anonymous, p.user_id, p.room_id)
         WHERE p.user_id = NEW.id AND NOT p.anonymous;
        RETURN NULL;
      END
      $$;

      CREATE OR REPLACE FUNCTION public.rooms_search_trigger() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        UPDATE posts p SET searchable = public.post_search_document(p.id, p.title, p.anonymous, p.user_id, p.room_id)
         WHERE p.room_id = NEW.id;
        RETURN NULL;
      END
      $$;

      DROP TRIGGER IF EXISTS posts_search_refresh ON posts;
      CREATE TRIGGER posts_search_refresh BEFORE INSERT OR UPDATE OF title, anonymous, user_id, room_id ON posts
        FOR EACH ROW EXECUTE FUNCTION public.posts_search_trigger();

      DROP TRIGGER IF EXISTS comments_search_refresh ON comments;
      CREATE TRIGGER comments_search_refresh BEFORE INSERT OR UPDATE OF content ON comments
        FOR EACH ROW EXECUTE FUNCTION public.comments_search_trigger();

      DROP TRIGGER IF EXISTS rich_texts_search_refresh ON action_text_rich_texts;
      CREATE TRIGGER rich_texts_search_refresh AFTER INSERT OR DELETE OR UPDATE OF body ON action_text_rich_texts
        FOR EACH ROW EXECUTE FUNCTION public.rich_texts_search_trigger();

      DROP TRIGGER IF EXISTS users_search_refresh ON users;
      CREATE TRIGGER users_search_refresh AFTER UPDATE OF username ON users
        FOR EACH ROW WHEN (OLD.username IS DISTINCT FROM NEW.username)
        EXECUTE FUNCTION public.users_search_trigger();

      DROP TRIGGER IF EXISTS rooms_search_refresh ON rooms;
      CREATE TRIGGER rooms_search_refresh AFTER UPDATE OF name ON rooms
        FOR EACH ROW WHEN (OLD.name IS DISTINCT FROM NEW.name)
        EXECUTE FUNCTION public.rooms_search_trigger();
    SQL

    DROP_SQL = <<~SQL
      DROP TRIGGER IF EXISTS posts_search_refresh ON posts;
      DROP TRIGGER IF EXISTS comments_search_refresh ON comments;
      DROP TRIGGER IF EXISTS rich_texts_search_refresh ON action_text_rich_texts;
      DROP TRIGGER IF EXISTS users_search_refresh ON users;
      DROP TRIGGER IF EXISTS rooms_search_refresh ON rooms;
      DROP FUNCTION IF EXISTS public.posts_search_trigger();
      DROP FUNCTION IF EXISTS public.comments_search_trigger();
      DROP FUNCTION IF EXISTS public.rich_texts_search_trigger();
      DROP FUNCTION IF EXISTS public.users_search_trigger();
      DROP FUNCTION IF EXISTS public.rooms_search_trigger();
      DROP FUNCTION IF EXISTS public.post_search_document(bigint, text, boolean, bigint, bigint);
      DROP FUNCTION IF EXISTS public.comment_search_document(bigint, text);
      DROP FUNCTION IF EXISTS public.search_document(text, text, text, text);
      DROP FUNCTION IF EXISTS public.search_html_text(text);
      DROP FUNCTION IF EXISTS public.search_key(text);
      DROP FUNCTION IF EXISTS public.search_fold(text);
      DROP TEXT SEARCH CONFIGURATION IF EXISTS public.brethreign_search;
    SQL

    module_function

    # True once the tables these objects hang off exist (a fresh database
    # before its schema is loaded has none).
    def applicable?(connection)
      connection.adapter_name.match?(/postg/i) &&
        %w[posts comments action_text_rich_texts users rooms].all? { |t| connection.table_exists?(t) } &&
        connection.column_exists?(:posts, :search_title) && connection.column_exists?(:comments, :searchable)
    end

    def install!(connection = ActiveRecord::Base.connection)
      return false unless applicable?(connection)

      connection.execute(SQL)
      true
    end

    def drop!(connection = ActiveRecord::Base.connection)
      connection.execute(DROP_SQL)
    end
  end
end

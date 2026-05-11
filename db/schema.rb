# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_05_11_210000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "ai_moderation_reviews", force: :cascade do |t|
    t.string "reviewable_type", null: false
    t.bigint "reviewable_id", null: false
    t.bigint "user_id"
    t.integer "status", default: 0, null: false
    t.string "severity", default: "none", null: false
    t.string "recommended_action", default: "allow", null: false
    t.string "categories", default: [], null: false, array: true
    t.float "score", default: 0.0, null: false
    t.string "summary"
    t.string "model"
    t.jsonb "raw_response", default: {}, null: false
    t.datetime "reviewed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["categories"], name: "index_ai_moderation_reviews_on_categories", using: :gin
    t.index ["reviewable_type", "reviewable_id"], name: "index_ai_moderation_reviews_on_reviewable"
    t.index ["reviewed_at"], name: "index_ai_moderation_reviews_on_reviewed_at"
    t.index ["severity"], name: "index_ai_moderation_reviews_on_severity"
    t.index ["status"], name: "index_ai_moderation_reviews_on_status"
    t.index ["user_id"], name: "index_ai_moderation_reviews_on_user_id"
  end

  create_table "announcements", force: :cascade do |t|
    t.integer "kind", default: 0, null: false
    t.string "kicker", limit: 80
    t.string "title", limit: 160, null: false
    t.text "body"
    t.bigint "user_id"
    t.datetime "published_at"
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind"], name: "index_announcements_on_kind"
    t.index ["published_at"], name: "index_announcements_on_published_at"
    t.index ["user_id"], name: "index_announcements_on_user_id"
  end

  create_table "bible_quiz_questions", force: :cascade do |t|
    t.string "kind", limit: 32, null: false
    t.text "prompt", null: false
    t.jsonb "choices", default: [], null: false
    t.integer "correct_index", null: false
    t.string "reference", limit: 80
    t.text "explanation"
    t.string "difficulty", limit: 16, default: "medium"
    t.string "fingerprint", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fingerprint"], name: "index_bible_quiz_questions_on_fingerprint", unique: true
    t.index ["kind"], name: "index_bible_quiz_questions_on_kind"
  end

  create_table "bible_verses", force: :cascade do |t|
    t.text "text", null: false
    t.string "reference"
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_bible_verses_on_active"
    t.index ["position"], name: "index_bible_verses_on_position"
  end

  create_table "bookmarks", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "post_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["post_id"], name: "index_bookmarks_on_post_id"
    t.index ["user_id", "post_id"], name: "index_bookmarks_on_user_id_and_post_id", unique: true
    t.index ["user_id"], name: "index_bookmarks_on_user_id"
  end

  create_table "brethren_cards", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "church_or_assembly"
    t.text "bio"
    t.string "occupation"
    t.string "whatsapp_number"
    t.string "email"
    t.boolean "is_complete", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_brethren_cards_on_user_id", unique: true
  end

  create_table "broadcasts", force: :cascade do |t|
    t.string "subject", limit: 200, null: false
    t.string "preheader", limit: 200
    t.bigint "sender_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "sent_at"
    t.integer "recipients_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["sender_id"], name: "index_broadcasts_on_sender_id"
    t.index ["status"], name: "index_broadcasts_on_status"
  end

  create_table "church_history_eras", force: :cascade do |t|
    t.string "slug", limit: 32, null: false
    t.text "summary"
    t.datetime "generated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_church_history_eras_on_slug", unique: true
  end

  create_table "church_history_figures", force: :cascade do |t|
    t.string "name", limit: 120, null: false
    t.string "slug", limit: 120, null: false
    t.integer "era", default: 0, null: false
    t.integer "birth_year"
    t.integer "death_year"
    t.string "claim", limit: 240
    t.text "featured_quote"
    t.text "bio"
    t.datetime "bio_generated_at"
    t.integer "sort_order", default: 0
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["era"], name: "index_church_history_figures_on_era"
    t.index ["slug"], name: "index_church_history_figures_on_slug", unique: true
  end

  create_table "comments", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "post_id", null: false
    t.bigint "parent_comment_id"
    t.text "content"
    t.datetime "edited_at"
    t.datetime "deleted_at"
    t.boolean "flagged", default: false, null: false
    t.integer "likes_count", default: 0, null: false
    t.integer "replies_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "moderation_status", default: 0, null: false
    t.string "moderation_blocked_reason", limit: 280
    t.index ["deleted_at"], name: "index_comments_on_deleted_at"
    t.index ["flagged"], name: "index_comments_on_flagged"
    t.index ["moderation_status"], name: "index_comments_on_moderation_status"
    t.index ["parent_comment_id"], name: "index_comments_on_parent_comment_id"
    t.index ["post_id", "created_at"], name: "index_comments_on_post_id_and_created_at"
    t.index ["post_id"], name: "index_comments_on_post_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "connection_requests", force: :cascade do |t|
    t.bigint "sender_id", null: false
    t.bigint "receiver_id", null: false
    t.integer "status", default: 0, null: false
    t.text "message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["receiver_id"], name: "index_connection_requests_on_receiver_id"
    t.index ["sender_id", "receiver_id"], name: "index_connection_requests_on_sender_id_and_receiver_id", unique: true
    t.index ["sender_id"], name: "index_connection_requests_on_sender_id"
    t.index ["status"], name: "index_connection_requests_on_status"
  end

  create_table "conversation_participants", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.bigint "user_id", null: false
    t.datetime "last_read_at"
    t.datetime "archived_at"
    t.datetime "muted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "user_id"], name: "index_conversation_participants_unique_pair", unique: true
    t.index ["conversation_id"], name: "index_conversation_participants_on_conversation_id"
    t.index ["user_id", "archived_at"], name: "index_conversation_participants_on_user_id_and_archived_at"
    t.index ["user_id"], name: "index_conversation_participants_on_user_id"
  end

  create_table "conversations", force: :cascade do |t|
    t.datetime "last_message_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["last_message_at"], name: "index_conversations_on_last_message_at"
  end

  create_table "follows", force: :cascade do |t|
    t.bigint "follower_id", null: false
    t.bigint "following_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["follower_id", "following_id"], name: "index_follows_on_follower_id_and_following_id", unique: true
    t.index ["follower_id"], name: "index_follows_on_follower_id"
    t.index ["following_id"], name: "index_follows_on_following_id"
  end

  create_table "game_attempts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "kind", default: 0, null: false
    t.integer "score", default: 0, null: false
    t.integer "max_score", default: 0, null: false
    t.integer "duration_ms"
    t.jsonb "details", default: {}, null: false
    t.datetime "played_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["kind"], name: "index_game_attempts_on_kind"
    t.index ["played_at"], name: "index_game_attempts_on_played_at"
    t.index ["user_id", "kind"], name: "index_game_attempts_on_user_id_and_kind"
    t.index ["user_id"], name: "index_game_attempts_on_user_id"
  end

  create_table "golden_breaths", force: :cascade do |t|
    t.text "text", null: false
    t.string "author_name"
    t.string "reference"
    t.string "source_url"
    t.boolean "active", default: true, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_golden_breaths_on_active"
    t.index ["position"], name: "index_golden_breaths_on_position"
  end

  create_table "invitations", force: :cascade do |t|
    t.bigint "inviter_id", null: false
    t.bigint "invited_user_id"
    t.string "email", null: false
    t.string "token", null: false
    t.text "message"
    t.datetime "accepted_at"
    t.datetime "last_sent_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_invitations_on_email"
    t.index ["invited_user_id"], name: "index_invitations_on_invited_user_id"
    t.index ["inviter_id", "email"], name: "index_invitations_on_inviter_id_and_email", unique: true
    t.index ["inviter_id"], name: "index_invitations_on_inviter_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "likes", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "likeable_type", null: false
    t.bigint "likeable_id", null: false
    t.integer "reaction_type", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "reaction_emoji"
    t.index ["likeable_type", "likeable_id", "reaction_emoji"], name: "index_likes_on_likeable_and_emoji"
    t.index ["likeable_type", "likeable_id"], name: "index_likes_on_likeable"
    t.index ["reaction_type"], name: "index_likes_on_reaction_type"
    t.index ["user_id", "likeable_type", "likeable_id"], name: "index_likes_on_user_and_likeable", unique: true
    t.index ["user_id"], name: "index_likes_on_user_id"
  end

  create_table "mentions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "mentionable_type", null: false
    t.bigint "mentionable_id", null: false
    t.string "mentioned_by_type", null: false
    t.bigint "mentioned_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["mentionable_type", "mentionable_id"], name: "index_mentions_on_mentionable"
    t.index ["mentionable_type", "mentionable_id"], name: "index_mentions_on_mentionable_type_and_mentionable_id"
    t.index ["mentioned_by_type", "mentioned_by_id"], name: "index_mentions_on_mentioned_by"
    t.index ["mentioned_by_type", "mentioned_by_id"], name: "index_mentions_on_mentioned_by_type_and_mentioned_by_id"
    t.index ["user_id", "mentionable_type", "mentionable_id"], name: "index_mentions_on_user_and_mentionable"
    t.index ["user_id"], name: "index_mentions_on_user_id"
  end

  create_table "message_blocks", force: :cascade do |t|
    t.bigint "blocker_id", null: false
    t.bigint "blocked_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blocked_id", "blocker_id"], name: "index_message_blocks_on_blocked_id_and_blocker_id"
    t.index ["blocked_id"], name: "index_message_blocks_on_blocked_id"
    t.index ["blocker_id", "blocked_id"], name: "index_message_blocks_on_blocker_id_and_blocked_id", unique: true
    t.index ["blocker_id"], name: "index_message_blocks_on_blocker_id"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.bigint "sender_id", null: false
    t.text "body", null: false
    t.datetime "edited_at"
    t.datetime "deleted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "likes_count", default: 0, null: false
    t.index ["conversation_id", "created_at"], name: "index_messages_on_conversation_id_and_created_at"
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["deleted_at"], name: "index_messages_on_deleted_at"
    t.index ["sender_id", "created_at"], name: "index_messages_on_sender_id_and_created_at"
    t.index ["sender_id"], name: "index_messages_on_sender_id"
  end

  create_table "moderation_logs", force: :cascade do |t|
    t.bigint "moderator_id", null: false
    t.string "action", null: false
    t.string "target_type", null: false
    t.bigint "target_id", null: false
    t.text "notes"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "ai_moderation_review_id"
    t.index ["action"], name: "index_moderation_logs_on_action"
    t.index ["ai_moderation_review_id"], name: "index_moderation_logs_on_ai_moderation_review_id"
    t.index ["created_at"], name: "index_moderation_logs_on_created_at"
    t.index ["moderator_id"], name: "index_moderation_logs_on_moderator_id"
    t.index ["target_type", "target_id"], name: "index_moderation_logs_on_target"
    t.index ["target_type", "target_id"], name: "index_moderation_logs_on_target_type_and_target_id"
  end

  create_table "notifications", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "actor_id"
    t.string "notifiable_type", null: false
    t.bigint "notifiable_id", null: false
    t.integer "notification_type", null: false
    t.datetime "read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_notifications_on_actor_id"
    t.index ["notifiable_type", "notifiable_id"], name: "index_notifications_on_notifiable"
    t.index ["notification_type"], name: "index_notifications_on_notification_type"
    t.index ["user_id", "created_at"], name: "index_notifications_on_user_id_and_created_at"
    t.index ["user_id", "read_at"], name: "index_notifications_on_user_id_and_read_at"
    t.index ["user_id"], name: "index_notifications_on_user_id"
  end

  create_table "post_links", force: :cascade do |t|
    t.bigint "source_post_id", null: false
    t.bigint "target_post_id", null: false
    t.string "link_type", default: "related"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source_post_id", "target_post_id"], name: "index_post_links_on_source_post_id_and_target_post_id", unique: true
    t.index ["source_post_id"], name: "index_post_links_on_source_post_id"
    t.index ["target_post_id"], name: "index_post_links_on_target_post_id"
  end

  create_table "post_tags", force: :cascade do |t|
    t.bigint "post_id", null: false
    t.bigint "tag_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["post_id", "tag_id"], name: "index_post_tags_on_post_id_and_tag_id", unique: true
    t.index ["post_id"], name: "index_post_tags_on_post_id"
    t.index ["tag_id"], name: "index_post_tags_on_tag_id"
  end

  create_table "posts", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "room_id"
    t.string "title"
    t.string "slug", null: false
    t.integer "status", default: 0, null: false
    t.boolean "featured", default: false, null: false
    t.integer "views_count", default: 0, null: false
    t.integer "likes_count", default: 0, null: false
    t.integer "comments_count", default: 0, null: false
    t.datetime "published_at"
    t.datetime "scheduled_for"
    t.boolean "allow_comments", default: true, null: false
    t.boolean "anonymous", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "reshares_count", default: 0, null: false
    t.integer "kind", default: 0, null: false
    t.integer "prayer_status", default: 0, null: false
    t.integer "intercessions_count", default: 0, null: false
    t.datetime "prayer_answered_at"
    t.integer "moderation_status", default: 0, null: false
    t.string "moderation_blocked_reason", limit: 280
    t.index ["featured"], name: "index_posts_on_featured"
    t.index ["kind"], name: "index_posts_on_kind"
    t.index ["moderation_status"], name: "index_posts_on_moderation_status"
    t.index ["prayer_status"], name: "index_posts_on_prayer_status"
    t.index ["published_at"], name: "index_posts_on_published_at"
    t.index ["room_id", "status", "published_at"], name: "index_posts_on_room_id_and_status_and_published_at"
    t.index ["room_id"], name: "index_posts_on_room_id"
    t.index ["scheduled_for"], name: "index_posts_on_scheduled_for", where: "(scheduled_for IS NOT NULL)"
    t.index ["slug"], name: "index_posts_on_slug", unique: true
    t.index ["status"], name: "index_posts_on_status"
    t.index ["user_id", "status"], name: "index_posts_on_user_id_and_status"
    t.index ["user_id"], name: "index_posts_on_user_id"
    t.index ["views_count"], name: "index_posts_on_views_count"
  end

  create_table "prayer_intercessions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "post_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["post_id"], name: "index_prayer_intercessions_on_post_id"
    t.index ["user_id", "post_id"], name: "index_prayer_intercessions_on_user_id_and_post_id", unique: true
    t.index ["user_id"], name: "index_prayer_intercessions_on_user_id"
  end

  create_table "profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.text "bio"
    t.string "location"
    t.string "faith_background"
    t.boolean "public_profile", default: true, null: false
    t.string "website"
    t.jsonb "social_links", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id"], name: "index_profiles_on_user_id", unique: true
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "endpoint", limit: 1024, null: false
    t.string "p256dh_key", null: false
    t.string "auth_key", null: false
    t.string "user_agent"
    t.datetime "last_pushed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "reports", force: :cascade do |t|
    t.bigint "reporter_id", null: false
    t.string "reportable_type", null: false
    t.bigint "reportable_id", null: false
    t.text "reason", null: false
    t.integer "status", default: 0, null: false
    t.bigint "reviewed_by_id"
    t.datetime "reviewed_at"
    t.text "resolution_notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["reportable_type", "reportable_id", "status"], name: "index_reports_on_reportable_type_and_reportable_id_and_status"
    t.index ["reportable_type", "reportable_id"], name: "index_reports_on_reportable"
    t.index ["reporter_id"], name: "index_reports_on_reporter_id"
    t.index ["reviewed_by_id"], name: "index_reports_on_reviewed_by_id"
    t.index ["status"], name: "index_reports_on_status"
  end

  create_table "reshares", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "post_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["post_id"], name: "index_reshares_on_post_id"
    t.index ["user_id", "post_id"], name: "index_reshares_on_user_id_and_post_id", unique: true
    t.index ["user_id"], name: "index_reshares_on_user_id"
  end

  create_table "resource_categories", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "icon"
    t.string "slug", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_resource_categories_on_position"
    t.index ["slug"], name: "index_resource_categories_on_slug", unique: true
  end

  create_table "resources", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "resource_category_id", null: false
    t.string "title", null: false
    t.text "description"
    t.integer "resource_type", default: 0, null: false
    t.string "url"
    t.string "slug", null: false
    t.boolean "approved", default: false, null: false
    t.bigint "approved_by_id"
    t.datetime "approved_at"
    t.integer "views_count", default: 0, null: false
    t.integer "downloads_count", default: 0, null: false
    t.boolean "featured", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["approved", "created_at"], name: "index_resources_on_approved_and_created_at"
    t.index ["approved"], name: "index_resources_on_approved"
    t.index ["approved_by_id"], name: "index_resources_on_approved_by_id"
    t.index ["featured"], name: "index_resources_on_featured"
    t.index ["resource_category_id"], name: "index_resources_on_resource_category_id"
    t.index ["resource_type"], name: "index_resources_on_resource_type"
    t.index ["slug"], name: "index_resources_on_slug", unique: true
    t.index ["user_id"], name: "index_resources_on_user_id"
  end

  create_table "room_memberships", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "room_id", null: false
    t.integer "role", default: 0, null: false
    t.boolean "notifications_enabled", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["role"], name: "index_room_memberships_on_role"
    t.index ["room_id"], name: "index_room_memberships_on_room_id"
    t.index ["user_id", "room_id"], name: "index_room_memberships_on_user_id_and_room_id", unique: true
    t.index ["user_id"], name: "index_room_memberships_on_user_id"
  end

  create_table "rooms", force: :cascade do |t|
    t.string "name", null: false
    t.text "description"
    t.string "slug", null: false
    t.integer "room_type", default: 0, null: false
    t.boolean "is_public", default: true, null: false
    t.text "rules"
    t.string "icon"
    t.string "color"
    t.integer "posts_count", default: 0, null: false
    t.integer "members_count", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["is_public"], name: "index_rooms_on_is_public"
    t.index ["position"], name: "index_rooms_on_position"
    t.index ["room_type"], name: "index_rooms_on_room_type"
    t.index ["slug"], name: "index_rooms_on_slug", unique: true
  end

  create_table "tags", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.integer "usage_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_tags_on_name", unique: true
    t.index ["slug"], name: "index_tags_on_slug", unique: true
    t.index ["usage_count"], name: "index_tags_on_usage_count"
  end

  create_table "user_reading_plans", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "plan_slug", null: false
    t.integer "current_day", default: 1, null: false
    t.date "started_on"
    t.date "last_completed_on"
    t.boolean "completed", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "plan_slug"], name: "index_user_reading_plans_on_user_id_and_plan_slug", unique: true
    t.index ["user_id"], name: "index_user_reading_plans_on_user_id"
  end

  create_table "user_risk_profiles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.integer "risk_level", default: 0, null: false
    t.float "risk_score", default: 0.0, null: false
    t.integer "flagged_reviews_count", default: 0, null: false
    t.integer "confirmed_violations_count", default: 0, null: false
    t.integer "dismissed_flags_count", default: 0, null: false
    t.datetime "last_flagged_at"
    t.datetime "last_action_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["last_flagged_at"], name: "index_user_risk_profiles_on_last_flagged_at"
    t.index ["risk_level"], name: "index_user_risk_profiles_on_risk_level"
    t.index ["user_id"], name: "index_user_risk_profiles_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.string "username", null: false
    t.integer "role", default: 0, null: false
    t.datetime "verified_at"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "dark_mode", default: false, null: false
    t.boolean "email_notifications_enabled", default: true, null: false
    t.string "provider"
    t.string "uid"
    t.datetime "last_seen_at"
    t.integer "current_breath_streak", default: 0, null: false
    t.integer "longest_breath_streak", default: 0, null: false
    t.date "streak_updated_on"
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["last_seen_at"], name: "index_users_on_last_seen_at"
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["role"], name: "index_users_on_role"
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ai_moderation_reviews", "users"
  add_foreign_key "announcements", "users"
  add_foreign_key "bookmarks", "posts"
  add_foreign_key "bookmarks", "users"
  add_foreign_key "brethren_cards", "users"
  add_foreign_key "broadcasts", "users", column: "sender_id"
  add_foreign_key "comments", "comments", column: "parent_comment_id"
  add_foreign_key "comments", "posts"
  add_foreign_key "comments", "users"
  add_foreign_key "connection_requests", "users", column: "receiver_id"
  add_foreign_key "connection_requests", "users", column: "sender_id"
  add_foreign_key "conversation_participants", "conversations"
  add_foreign_key "conversation_participants", "users"
  add_foreign_key "follows", "users", column: "follower_id"
  add_foreign_key "follows", "users", column: "following_id"
  add_foreign_key "game_attempts", "users"
  add_foreign_key "invitations", "users", column: "invited_user_id"
  add_foreign_key "invitations", "users", column: "inviter_id"
  add_foreign_key "likes", "users"
  add_foreign_key "mentions", "users"
  add_foreign_key "message_blocks", "users", column: "blocked_id"
  add_foreign_key "message_blocks", "users", column: "blocker_id"
  add_foreign_key "messages", "conversations"
  add_foreign_key "messages", "users", column: "sender_id"
  add_foreign_key "moderation_logs", "ai_moderation_reviews"
  add_foreign_key "moderation_logs", "users", column: "moderator_id"
  add_foreign_key "notifications", "users"
  add_foreign_key "notifications", "users", column: "actor_id"
  add_foreign_key "post_links", "posts", column: "source_post_id"
  add_foreign_key "post_links", "posts", column: "target_post_id"
  add_foreign_key "post_tags", "posts"
  add_foreign_key "post_tags", "tags"
  add_foreign_key "posts", "rooms"
  add_foreign_key "posts", "users"
  add_foreign_key "prayer_intercessions", "posts"
  add_foreign_key "prayer_intercessions", "users"
  add_foreign_key "profiles", "users"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "reports", "users", column: "reporter_id"
  add_foreign_key "reports", "users", column: "reviewed_by_id"
  add_foreign_key "reshares", "posts"
  add_foreign_key "reshares", "users"
  add_foreign_key "resources", "resource_categories"
  add_foreign_key "resources", "users"
  add_foreign_key "resources", "users", column: "approved_by_id"
  add_foreign_key "room_memberships", "rooms"
  add_foreign_key "room_memberships", "users"
  add_foreign_key "user_reading_plans", "users"
  add_foreign_key "user_risk_profiles", "users"
end

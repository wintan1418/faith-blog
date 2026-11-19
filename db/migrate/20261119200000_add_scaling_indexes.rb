# frozen_string_literal: true

# Indexes for the hot read paths (feed, profiles, alerts, analytics), and
# drop exact duplicates. Built CONCURRENTLY so writes never wait on them.
class AddScalingIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  # Post.published: status published (1) and moderation approved (0).
  PUBLISHED = "status = 1 AND moderation_status = 0"

  def up
    enable_extension "pg_trgm"

    add_index :reshares, :created_at, algorithm: :concurrently, if_not_exists: true
    add_index :reshares, [ :user_id, :created_at ], algorithm: :concurrently, if_not_exists: true

    add_index :posts, :published_at, order: { published_at: :desc }, where: PUBLISHED,
              name: "index_posts_published_feed", algorithm: :concurrently, if_not_exists: true
    add_index :posts, [ :user_id, :published_at ], order: { published_at: :desc }, where: PUBLISHED,
              name: "index_posts_published_by_user", algorithm: :concurrently, if_not_exists: true

    add_index :notifications, [ :user_id, :created_at ], order: { created_at: :desc }, where: "read_at IS NULL",
              name: "index_notifications_unread_by_user", algorithm: :concurrently, if_not_exists: true

    add_index :ahoy_events, :time, algorithm: :concurrently, if_not_exists: true

    # BrethrenSuggestions: Profile.where("skills && ARRAY[...]")
    add_index :profiles, :skills, using: :gin, algorithm: :concurrently, if_not_exists: true

    # People search: users.username ILIKE '%q%'
    add_index :users, :username, using: :gin, opclass: :gin_trgm_ops,
              name: "index_users_on_username_trgm", algorithm: :concurrently, if_not_exists: true

    # Exact duplicates of index_mentions_on_mentionable / _on_mentioned_by /
    # index_moderation_logs_on_target (same columns, same order, no predicate).
    remove_index :mentions, name: "index_mentions_on_mentionable_type_and_mentionable_id", algorithm: :concurrently, if_exists: true
    remove_index :mentions, name: "index_mentions_on_mentioned_by_type_and_mentioned_by_id", algorithm: :concurrently, if_exists: true
    remove_index :moderation_logs, name: "index_moderation_logs_on_target_type_and_target_id", algorithm: :concurrently, if_exists: true

    # Nothing orders by views_count alone (only inside an engagement expression).
    remove_index :posts, name: "index_posts_on_views_count", algorithm: :concurrently, if_exists: true
  end

  def down
    add_index :posts, :views_count, algorithm: :concurrently, if_not_exists: true
    add_index :moderation_logs, [ :target_type, :target_id ], algorithm: :concurrently, if_not_exists: true
    add_index :mentions, [ :mentioned_by_type, :mentioned_by_id ], algorithm: :concurrently, if_not_exists: true
    add_index :mentions, [ :mentionable_type, :mentionable_id ], algorithm: :concurrently, if_not_exists: true

    remove_index :users, name: "index_users_on_username_trgm", algorithm: :concurrently, if_exists: true
    remove_index :profiles, :skills, algorithm: :concurrently, if_exists: true
    remove_index :ahoy_events, :time, algorithm: :concurrently, if_exists: true
    remove_index :notifications, name: "index_notifications_unread_by_user", algorithm: :concurrently, if_exists: true
    remove_index :posts, name: "index_posts_published_by_user", algorithm: :concurrently, if_exists: true
    remove_index :posts, name: "index_posts_published_feed", algorithm: :concurrently, if_exists: true
    remove_index :reshares, [ :user_id, :created_at ], algorithm: :concurrently, if_exists: true
    remove_index :reshares, :created_at, algorithm: :concurrently, if_exists: true
  end
end

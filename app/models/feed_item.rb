# frozen_string_literal: true

# Lightweight wrapper for things that appear in a feed: either an
# original post, or a reshare (still pointing at a post but attributed
# to the user who reshared).
FeedItem = Struct.new(:post, :reshared_by, :timestamp, keyword_init: true) do
  def self.from_post(post)
    new(post: post, reshared_by: nil, timestamp: post.published_at || post.created_at)
  end

  def self.from_reshare(reshare)
    new(post: reshare.post, reshared_by: reshare.user, timestamp: reshare.created_at)
  end

  def self.merge(posts:, reshares:)
    items = posts.map { |p| from_post(p) } + reshares.map { |r| from_reshare(r) }
    items.sort_by { |i| -i.timestamp.to_i }
  end

  def reshared?
    reshared_by.present?
  end
end

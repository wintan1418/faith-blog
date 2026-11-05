# frozen_string_literal: true

# /sitemap.xml: every public page Google should know about, so new breaths,
# rooms and scripture pages are found within days.
class SitemapsController < ApplicationController
  skip_before_action :authenticate_user!, raise: false

  POSTS_LIMIT = 5_000

  # Verses people search for most; each gets its scripture page.
  POPULAR_VERSES = [
    "John 3:16", "Jeremiah 29:11", "Philippians 4:13", "Romans 8:28", "Proverbs 3:5-6", "Isaiah 41:10",
    "Psalm 23", "Joshua 1:9", "Matthew 6:33", "Romans 12:2", "Philippians 4:6-7", "Psalm 46:10",
    "2 Timothy 1:7", "Isaiah 40:31", "Matthew 11:28", "Galatians 5:22-23", "Hebrews 11:1", "Romans 10:9",
    "1 Corinthians 13:4-7", "Psalm 91", "Ephesians 2:8-9", "2 Corinthians 5:17", "Matthew 28:19-20",
    "John 14:6", "Psalm 121", "1 Peter 5:7", "James 1:5", "Romans 5:8", "Lamentations 3:22-23",
    "Psalm 27:1", "Proverbs 18:10", "Isaiah 53:5", "John 1:1", "Micah 6:8", "Psalm 37:4",
    "Deuteronomy 31:6", "Matthew 5:16", "John 16:33", "Romans 15:13", "1 John 1:9", "Psalm 34:18",
    "Hebrews 13:5", "Psalm 139:14", "Colossians 3:23", "Numbers 6:24-26", "Zephaniah 3:17",
    "Ephesians 6:10-11", "1 Thessalonians 5:16-18", "Matthew 7:7", "Psalm 51:10"
  ].freeze

  def show
    @posts = Post.published.where(room_id: [ nil, *Room.public_rooms.select(:id) ])
                 .order(published_at: :desc).limit(POSTS_LIMIT).select(:id, :slug, :updated_at)
    @rooms = Room.public_rooms.select(:id, :slug, :updated_at)
    @resources = Resource.approved.select(:id, :slug, :updated_at)
    references = (POPULAR_VERSES + BibleVerse.where(active: true).pluck(:reference)).compact_blank.uniq
    @scripture_slugs = references.map { |ref| self.class.scripture_slug(ref) }.uniq

    expires_in 1.hour, public: true
    render formats: [ :xml ]
  end

  # "1 John 3:16" -> "1-john-3-16" (what ScripturePagesController reads back).
  def self.scripture_slug(reference)
    reference.to_s.downcase.gsub(/[^a-z0-9]+/, "-").delete_prefix("-").delete_suffix("-")
  end
end

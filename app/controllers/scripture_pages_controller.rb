# frozen_string_literal: true

# A page per scripture reference — /scripture/john-3-16 — showing the verse
# text (via the cached ScriptureLookup) and every published breath that
# mentions it. Public: testimony around a verse is for everyone.
class ScripturePagesController < ApplicationController
  def show
    @reference = parse_slug(params[:slug])
    raise ActiveRecord::RecordNotFound unless @reference

    @verse = ScriptureLookup.lookup(@reference)
    @posts = posts_mentioning(@reference)
  end

  private

  # "1-john-3-16" → "1 John 3:16" · "psalm-23" → "Psalm 23" ·
  # "john-3-16-18" → "John 3:16-18". Trailing numbers are chapter/verse;
  # whatever remains in front (including a leading 1/2/3) is the book.
  def parse_slug(slug)
    parts = slug.to_s.downcase.split("-").reject(&:blank?)
    return nil if parts.empty?

    nums = []
    nums.unshift(parts.pop) while parts.any? && parts.last.match?(/\A\d{1,3}\z/) && nums.size < 3
    return nil if nums.empty? || parts.empty?

    book = parts.map { |p| p.match?(/\A[123]\z/) ? p : p.capitalize }.join(" ")
    case nums.size
    when 1 then "#{book} #{nums[0]}"
    when 2 then "#{book} #{nums[0]}:#{nums[1]}"
    else        "#{book} #{nums[0]}:#{nums[1]}-#{nums[2]}"
    end
  end

  def posts_mentioning(reference)
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(reference)}%"
    Post.published
        .left_joins(:rich_text_content)
        .where("action_text_rich_texts.body ILIKE :p OR posts.title ILIKE :p", p: pattern)
        .includes(:user, :room, :tags, :rich_text_content)
        .recent
        .limit(30)
  end
end

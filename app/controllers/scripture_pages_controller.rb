# frozen_string_literal: true

# Public scripture pages for the whole Bible: /scripture/psalm-23 (a chapter),
# /scripture/psalm-101-3 (a verse), /scripture/genesis-1-11-12 (a range), and
# the /scripture index of books and chapters.
#
# Each page shows the text (KJV, WEB, BSB, from the database), the stored
# AI-written explanation if there is one (never generated here), the verses
# around it, cross-references and the breaths that quote it. Any other
# spelling of a reference ("psalms-23", "1-cor-13-4-to-7") 301s to its one
# canonical address.
class ScripturePagesController < ApplicationController
  DISCUSSION_LIMIT = 6

  def index
    @popular = Scripture::Catalog.popular.reject(&:chapter?).first(40)
  end

  def show
    slug = params[:slug].to_s
    @reference = Scripture::Reference.from_slug(slug)
    return redirect_to_book_or_404(slug) unless @reference
    return redirect_to(scripture_page_path(@reference.slug), status: :moved_permanently) if @reference.slug != slug

    @insight = ScriptureInsight.find_by(slug: @reference.slug)
    @passage = Scripture::Passage.new(@reference)
    @cross_references = ScriptureCrossReference.top_for(@reference)
    @cross_reference_texts = first_verse_texts(@cross_references)
    @popular_here = @reference.chapter? ? Scripture::Catalog.popular_in(@reference.book, @reference.chapter) : []
    discussions = Post.scripture_discussable.where(id: ScriptureCitation.matching(@reference).select(:post_id))
    @posts = discussions.includes(:user, :rich_text_content).recent.limit(DISCUSSION_LIMIT).to_a
    @posts_total = @posts.size < DISCUSSION_LIMIT ? @posts.size : discussions.count
    load_daily_bible
  end

  private

  # "Have you read your Bible today?" on whole-chapter pages, for members.
  # Never lets the page fail.
  def load_daily_bible
    return unless user_signed_in? && @reference.chapter?

    @bible_habit = BibleHabit.for(current_user)
  rescue StandardError => e
    Rails.logger.warn("[daily_bible] scripture page: #{e.class}: #{e.message}")
    @bible_habit = nil
  end

  # "/scripture/genesis" → the book on the index; anything else is a 404.
  def redirect_to_book_or_404(slug)
    book = Scripture::Canon.find(slug.tr("-", " "))
    raise ActiveRecord::RecordNotFound unless book

    redirect_to scripture_index_path(anchor: book.slug), status: :moved_permanently
  end

  # KJV text of the first verse of each cross-reference, in one query.
  def first_verse_texts(references)
    return {} if references.empty?

    locations = references.map { |r| ScriptureVerse.where(book: r.book.position, chapter: r.chapter, verse: r.verse_start || 1) }
    ScriptureVerse.where(translation: ScriptureVerse::PRIMARY)
                  .merge(locations.reduce(:or))
                  .pluck(:book, :chapter, :verse, :text)
                  .to_h { |b, c, v, text| [ [ b, c, v ], text ] }
  end
end

# frozen_string_literal: true

# The written part of a scripture page: a plain-English explanation, the
# context (who, when, why) and a few reflection questions. Generated once by
# ScriptureInsightJob and stored; pages never call the AI themselves.
class ScriptureInsight < ApplicationRecord
  # A newly written page goes to the next IndexNow batch.
  include SearchIndexable

  # Never write more than this many pages in total (cost guard).
  CAP = 2_000

  validates :reference, :slug, :explanation, :context, :generated_at, presence: true
  validates :slug, uniqueness: true

  def scripture_reference
    Scripture::Reference.from_slug(slug)
  end

  def search_indexable? = true

  def search_index_urls
    [ search_url_helpers.scripture_page_url(slug) ]
  end

  def question_list
    Array(questions).map(&:to_s).compact_blank.first(3)
  end
end

# frozen_string_literal: true

# Opt a model into IndexNow: include this and define
#
#   search_indexable? — true only for a public page search engines may index
#   search_index_urls — the public URL(s) of that page
#
# When a record is created or edited (and is indexable), its URLs join the
# next IndexNow batch. Edits that only bump counters (likes, views, ...) don't
# count. Records that go live without callbacks (update_columns) call
# queue_for_search_engines(force: true) themselves.
module SearchIndexable
  extend ActiveSupport::Concern

  # Attribute changes that don't change what the page says.
  QUIET_CHANGE = /\A(searchable|.*_count|.*_score)\z/

  def self.models
    Rails.autoloaders.main.eager_load_dir(Rails.root.join("app/models").to_s) unless Rails.application.config.eager_load
    ApplicationRecord.descendants.select { |model| model.include?(self) }
  end

  included do
    after_commit :queue_for_search_engines, on: %i[create update]
  end

  class_methods do
    # Records worth checking when collecting "changed since" URLs.
    def search_index_candidates(since)
      where(updated_at: since..)
    end
  end

  def search_indexable?
    false
  end

  def search_index_urls
    []
  end

  def queue_for_search_engines(force: false)
    return unless IndexNow.enabled?
    return unless force || search_index_relevant_change?
    return unless search_indexable?

    SearchIndexing.queue(search_index_urls, source: self.class.name)
  rescue StandardError => e
    # Never let indexing break a save.
    Rails.logger.warn("[IndexNow] could not queue #{self.class.name}##{id}: #{e.class}: #{e.message}")
  end

  private

  # A touch (rich text edits touch the record) counts; counter bumps don't.
  def search_index_relevant_change?
    changed = saved_changes.keys - [ "updated_at" ]
    changed.empty? || changed.any? { |name| !name.match?(QUIET_CHANGE) }
  end

  def search_url_helpers
    SearchIndexing.url_helpers
  end
end

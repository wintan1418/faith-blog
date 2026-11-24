# frozen_string_literal: true

require "test_helper"

class SearchTermsRefreshJobTest < ActiveJob::TestCase
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @author = create_member("lexicon_writer")
    @public_room = Room.create!(name: "Lexicon Hall", description: "x")
    @private_room = Room.create!(name: "Lexicon Vault", description: "x", is_public: false)
  end

  def breath(text, **attrs)
    2.times do |i| # a word needs two breaths to count
      Post.create!({ user: @author, room: @public_room, title: "Breath #{i}", content: text, status: :published,
                     moderation_status: :approved }.merge(attrs))
    end
  end

  test "builds the word list from public breaths only" do
    breath("sunflower meadow")
    breath("classifiedword", room: @private_room)
    breath("secretanonword", anonymous: true)
    breath("prayerword", prayer_status: :prayer_pending)
    breath("draftword", status: :draft)

    SearchTermsRefreshJob.perform_now
    terms = SearchTerm.pluck(:term)
    assert_includes terms, "sunflower"
    %w[classifiedword secretanonword prayerword draftword].each { |w| refute_includes terms, w }
  end

  test "suggestions come from that list" do
    breath("sunflower meadow")
    SearchTermsRefreshJob.perform_now
    assert_equal "sunflower", SiteSearch::Suggester.new(SiteSearch::Query.new("sunflowr")).suggestion
    assert_nil SiteSearch::Suggester.new(SiteSearch::Query.new("sunflower")).suggestion
  end

  test "prunes old search log rows" do
    SearchQuery.create!(query: "old", tab: "top", created_at: 200.days.ago)
    SearchQuery.create!(query: "new", tab: "top")
    SearchTermsRefreshJob.perform_now
    assert_equal [ "new" ], SearchQuery.pluck(:query)
  end

  test "its concurrency key accepts any arguments" do
    assert_nothing_raised { SearchTermsRefreshJob.new.concurrency_key }
    assert_nothing_raised { SearchTermsRefreshJob.new(1, foo: 2).concurrency_key }
  end
end

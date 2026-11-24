# frozen_string_literal: true

require "test_helper"

class SiteSearchQueryTest < ActiveSupport::TestCase
  def q(text, **opts) = SiteSearch::Query.new(text, **opts)

  test "words, phrases, exclusions, from: and a prefix on the last word" do
    query = q('"good shepherd" psalm -law from:@Grace_Okafor')
    assert_equal "grace_okafor", query.from_username
    assert_equal [ "good shepherd" ], query.phrases
    assert_equal [ "psalm" ], query.terms
    assert_equal [ "law" ], query.excluded
    assert_equal "('good' <-> 'shepherd') & 'psalm':* & !('law')", query.tsquery
  end

  test "no prefix once the word is finished, or when asked not to" do
    assert_equal "'grace'", q("grace ").tsquery
    assert_equal "'grace'", q("grace", prefix: false).tsquery
  end

  test "only letters and digits reach the tsquery" do
    assert_match(/\A[a-z':* &]+\z/, q("a'); DROP TABLE posts; --").tsquery)
    tsquery = q("hello & world | !x :* <-> 'quote'").tsquery
    assert_no_match(/[|;]/, tsquery)
    assert_equal "", q("-only -exclusions").tsquery
    assert_equal "", q("!!! ???").tsquery
  end

  test "fancy letters are normalized (NFKC)" do
    assert_equal "'teenager':*", q("𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿").tsquery
    assert_equal "who is a teenager", q("𝗪𝗵𝗼 𝗜𝘀 𝗮 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿").plain_text.downcase
  end

  test "length and term count are bounded" do
    assert_operator q("word " * 200).text.length, :<=, SiteSearch::Query::MAX_LENGTH
    assert_operator q((1..50).map { |i| "w#{i}" }.join(" ")).terms.size, :<=, SiteSearch::Query::MAX_TERMS
  end

  test "with_text keeps from:" do
    assert_equal "grace_okafor", q("from:grace_okafor amazng").with_text("amazing").from_username
  end
end

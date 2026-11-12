# frozen_string_literal: true

require "test_helper"

class FeedBlogLinksTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    sign_in create_member("blog_reader")
  end

  test "the feed links to the blog and shows the latest guides" do
    get feed_path
    assert_response :success
    assert_select "a.fc-rail-link[href=?]", blog_path, text: /Blog/
    assert_select ".fc-blog-card a[href=?]", blog_path
    newest = BlogArticle.all.max_by { |a| [ a.date.jd, -a.order ] }
    assert_select ".fc-blog-card a[href=?]", blog_article_path(newest.slug)
  end
end

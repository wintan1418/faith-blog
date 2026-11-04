# frozen_string_literal: true

require "test_helper"

# Fixes for the QA board's "To Do (Bugs)" list (4 Nov 2026).
class QaBoardFixesNov4Test < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @pass = SecureRandom.base58(16)
    @ada = User.create!(username: "ada_qa4", email: "ada-qa4@example.com", password: @pass, password_confirmation: @pass)
  end

  # ── Published breaths left in Drafts ──

  test "publishing a draft takes it out of Drafts, and Drafts is never shown from a saved copy" do
    draft = @ada.posts.create!(content: "Still thinking about this one.", status: :draft)
    sign_in @ada

    get drafts_path
    assert_select "meta[name='turbo-cache-control'][content='no-cache']"
    assert_select "a[href=?]", edit_post_path(draft)

    patch post_path(draft), params: { post: { content: "Ready now.", status: "published" } }
    assert draft.reload.published?
    assert draft.published_at.present?

    get drafts_path
    assert_select "a[href=?]", edit_post_path(draft), count: 0
  end

  # ── Game share: Back reopened the composer; Cancel did nothing ──

  test "the New breath page publishes in place and both Cancels leave the page" do
    sign_in @ada
    get new_post_path(share_game: "quiz", score: 5, total: 5)
    assert_response :success
    assert_select "form.fc-composer-form[data-turbo-action='replace']"
    assert_select ".fc-composer-bar a[data-action~='click->composer-modal#close']", text: "Cancel"
    assert_select ".fc-composer-footer button[data-action~='click->composer-modal#close']", text: "Cancel"
  end

  test "the pop-up composer on the feed keeps normal history" do
    sign_in @ada
    get feed_path
    assert_select "dialog form.fc-composer-form:not([data-turbo-action])"
  end

  # ── Brethren card couldn't scroll with the keyboard open (Android sheet) ──

  test "android opens new/edit pages full screen, not in a bottom sheet" do
    get "/configurations/android_v1.json"
    modal = response.parsed_body["rules"].find { |r| r.dig("properties", "context") == "modal" }
    assert_equal "hotwire://fragment/web", modal.dig("properties", "uri")
    assert_includes modal["patterns"], "/edit$"
  end
end

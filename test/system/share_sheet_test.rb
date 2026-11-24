# frozen_string_literal: true

require "application_system_test_case"

# "Snapshot for status" and "Share as thread": the sheet opens with a live
# preview, switches between Story, Square and Portrait and light and dark,
# and a thread becomes one card per item.
class ShareSheetTest < ApplicationSystemTestCase
  include Warden::Test::Helpers

  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    seen = { welcomed_at: Time.current, seen_release_id: Announcement.maximum(:id).to_i,
             tour_completed_at: Time.current, onboarding_dismissed_at: Time.current }
    @member = create_member("sheet_member", **seen)
    author = create_member("sheet_author", accent_color: "violet")
    @post = Post.create!(user: author, title: "𝗪𝗵𝗼 𝗜𝘀 𝗮 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿? (𝟱)", content: "Listen before you lecture. 🙏 " * 30,
                         status: :published, moderation_status: :approved, published_at: 1.hour.ago)
    2.times { |i| Comment.create!(user: create_member("sheet_replier_#{i}"), post: @post, content: "A kind reply number #{i}") }
    login_as @member, scope: :user
  end

  teardown { Warden.test_reset! }

  def open_from_menu(item)
    within(".post-reactions-bar .fc-share") do
      find("button.fc-breath-action").click
      click_on item
    end
    assert_selector "dialog.share-sheet canvas.share-sheet-canvas", wait: 10
  end

  def canvas_sizes
    page.evaluate_script(%(Array.from(document.querySelectorAll("dialog.share-sheet canvas")).map(c => [c.width, c.height])))
  end

  test "the snapshot sheet previews every format and theme" do
    visit post_path(@post)
    open_from_menu "Snapshot for status"

    find("dialog.share-sheet [data-theme-choice=light]").click
    { "story" => [ 1080, 1920 ], "square" => [ 1080, 1080 ], "portrait" => [ 1080, 1350 ] }.each do |format, size|
      find("dialog.share-sheet [data-format=#{format}]").click
      assert_selector "dialog.share-sheet [data-format=#{format}][aria-checked=true]"
      assert_selector "dialog.share-sheet .share-sheet-stage[data-preview-format=#{format}][data-preview-theme=light]"
      assert_equal [ size ], canvas_sizes
    end

    find("dialog.share-sheet [data-theme-choice=dark]").click
    assert_selector "dialog.share-sheet .share-sheet-stage[data-preview-theme=dark][data-preview-format=portrait]"
    corner = page.evaluate_script(%(Array.from(document.querySelector("dialog.share-sheet canvas").getContext("2d").getImageData(4, 4, 1, 1).data)))
    assert_operator corner[0..2].sum, :<, 120, "the dark card has a dark frame"
    assert_selector "[data-testid=share-download]:not([disabled])"
  end

  test "a thread becomes one card per item" do
    visit post_path(@post)
    open_from_menu "Share as thread"

    assert_selector "dialog.share-sheet canvas.share-sheet-canvas", count: 3
    assert_selector "dialog.share-sheet .share-slide figcaption", text: "1/3"
    find("dialog.share-sheet .share-sheet-close").click
    assert_no_selector "dialog.share-sheet"
  end
end

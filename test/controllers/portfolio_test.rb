# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class PortfolioTest < ActionDispatch::IntegrationTest
  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")

  def png(name = "shot.png")
    path = Rails.root.join("tmp", "#{SecureRandom.hex(3)}-#{name}")
    File.binwrite(path, PNG)
    Rack::Test::UploadedFile.new(path, "image/png")
  end

  def pdf
    path = Rails.root.join("tmp", "case-#{SecureRandom.hex(3)}.pdf")
    File.binwrite(path, "%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF")
    Rack::Test::UploadedFile.new(path, "application/pdf")
  end

  setup do
    @me = create_member("pf_owner")
    sign_in @me
  end

  test "add a piece of work with photos and a PDF, then see it on its own page" do
    post settings_portfolio_items_path, params: { portfolio_item: {
      title: "Church giving checkout", summary: "One-tap giving", category: "Software & apps", contribution: "Lead engineer",
      link_url: "https://example.org/app", skills_list: "Rails, Payments", completed_month: "2024-08",
      description: "We cut giving to one tap.", images: [ png, png("b.png") ], document: pdf
    } }
    item = @me.portfolio_items.sole
    assert_redirected_to portfolio_work_path(@me.username, item)

    follow_redirect!
    assert_select "h1.pfw-title", text: "Church giving checkout"
    assert_select ".pfw-photo", count: 2
    assert_select "a.pfw-visit[href='https://example.org/app']"
    assert_select ".pfw-doc .msg-doc-name", text: /case-.*\.pdf/
    assert_select ".pfw-skills .pro-skill", count: 2
    assert_equal Date.new(2024, 8, 1), item.completed_on
  end

  test "links must be https and the PDF must really be a PDF" do
    post settings_portfolio_items_path, params: { portfolio_item: { title: "X", link_url: "javascript:alert(1)" } }
    assert_response :unprocessable_entity

    fake = Rack::Test::UploadedFile.new(png.path, "application/pdf", original_filename: "notes.pdf")
    post settings_portfolio_items_path, params: { portfolio_item: { title: "X", document: fake } }
    assert_response :unprocessable_entity
    assert_equal 0, PortfolioItem.where(user: @me).count
  end

  test "editing adds photos to the ones kept, and can remove one" do
    item = @me.portfolio_items.new(title: "Photo series")
    item.images.attach([ png, png("b.png") ])
    item.save!
    first = item.images.attachments.first

    patch settings_portfolio_item_path(item), params: { portfolio_item: { title: "Photo series", images: [ png("c.png") ],
                                                                         remove_image_ids: [ first.id ] } }
    assert_equal 2, item.reload.images.attachments.size
    assert_not_includes item.images.attachments.map(&:id), first.id
  end

  test "pieces can be moved up and down" do
    a = @me.portfolio_items.create!(title: "A")
    b = @me.portfolio_items.create!(title: "B")
    c = @me.portfolio_items.create!(title: "C")

    patch move_settings_portfolio_item_path(c, direction: "up")
    assert_equal %w[A C B], @me.portfolio_items.reload.map(&:title)
    patch move_settings_portfolio_item_path(a, direction: "up") # already first: no change
    assert_equal %w[A C B], @me.portfolio_items.reload.map(&:title)
    patch move_settings_portfolio_item_path(a, direction: "down")
    assert_equal %w[C A B], @me.portfolio_items.reload.map(&:title)
    assert b
  end

  test "the Portfolio tab: always for the owner, for visitors only when there's work" do
    get user_path(@me.username)
    assert_select "a.profile-tab", text: "Portfolio"
    get user_path(@me.username, tab: "portfolio")
    assert_select ".pf-card--add"

    visitor = create_member("pf_visitor")
    sign_in visitor
    get user_path(@me.username)
    assert_select "a.profile-tab", text: "Portfolio", count: 0

    @me.portfolio_items.create!(title: "Youth camp", category: "Events")
    get user_path(@me.username, tab: "portfolio")
    assert_select "a.profile-tab.is-active", text: "Portfolio"
    assert_select ".pf-card .pf-title", text: "Youth camp"
    assert_select ".pf-card--add", count: 0
  end

  test "someone else can't edit your work" do
    item = create_member("pf_other").portfolio_items.create!(title: "Theirs")
    patch settings_portfolio_item_path(item), params: { portfolio_item: { title: "Mine now" } }
    assert_response :not_found
    assert_equal "Theirs", item.reload.title
  end

  test "work the safety check flags is hidden from others, shown to the owner with a note, and back after a clean edit" do
    flagged = Ai::Moderation::Result.new(safe: false, severity: "high", categories: [ "explicit_adult" ], score: 0.9,
                                         summary: "explicit", recommended_action: "block", raw_response: {}, model: "test")
    clean = Ai::Moderation::Result.new(safe: true, severity: "none", categories: [], score: 0.0, summary: "", recommended_action: "allow", raw_response: {}, model: "test")

    item = Ai::Moderation::Reviewer.stub(:call, flagged) { @me.portfolio_items.create!(title: "Bad one") }
    assert item.reload.hidden?
    assert AiModerationReview.exists?(reviewable: item)
    assert @me.notifications.where(notification_type: :content_removed, notifiable: item).exists?

    get portfolio_work_path(@me.username, item)
    assert_select ".pfw-hidden"
    get notifications_path
    assert_response :success
    assert_match(/hidden from your portfolio/, response.body)

    sign_in create_member("pf_viewer")
    get portfolio_work_path(@me.username, item)
    assert_response :not_found

    sign_in @me
    Ai::Moderation::Reviewer.stub(:call, clean) { patch settings_portfolio_item_path(item), params: { portfolio_item: { title: "Fixed one" } } }
    assert_not item.reload.hidden?
  end

  test "a private profile keeps its work private" do
    @me.profile.update!(public_profile: false)
    item = @me.portfolio_items.create!(title: "Quiet work")
    sign_in create_member("pf_stranger")
    get portfolio_work_path(@me.username, item)
    assert_response :not_found
  end
end

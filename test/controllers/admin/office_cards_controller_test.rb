# frozen_string_literal: true

require "test_helper"

# Breath images, flyer → breath, and Copy buttons on Office cards.
class Admin::OfficeCardsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    ENV["OFFICE_STUB"] = "1"
    @admin = create_member("office_admin_#{SecureRandom.hex(3)}", role: :admin)
    @conversation = @admin.office_conversations.create!(title: "Imported notes")
    sign_in @admin
  end

  teardown { ENV.delete("OFFICE_STUB") }

  def png_bytes = Ai::Office::ImageGenerator.new.generate(prompt: "x", size: "square").bytes

  def png_upload(name = "photo.png", content_type: "image/png", bytes: png_bytes)
    file = Tempfile.new([ "upload", File.extname(name) ])
    file.binmode
    file.write(bytes)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, content_type, true, original_filename: name)
  end

  # Shaped like production cards made before this change: no ids in results.
  def flyer_card
    message = @conversation.messages.new(role: :tool, content: "{}", payload: {
      "tool_call_id" => "f#{SecureRandom.hex(2)}", "name" => "generate_flyer", "result" => { "status" => "image_ready" },
      "card" => { "kind" => "flyer", "brief" => "Hidden years flyer", "size" => "square", "model" => "stub" }
    })
    message.image.attach(io: StringIO.new(png_bytes), filename: "flyer.png", content_type: "image/png")
    message.save!
    message
  end

  def breath_card(attrs = {})
    @conversation.messages.create!(role: :tool, content: "{}", payload: {
      "tool_call_id" => "b#{SecureRandom.hex(2)}", "name" => "draft_breath", "result" => { "status" => "card_shown" },
      "card" => { "kind" => "breath", "status" => "draft", "title" => "The Hidden Years", "body" => "Long body " * 300, "prayer" => false, "author" => @admin.username }.merge(attrs)
    })
  end

  def posted_breath
    card = breath_card
    post = Ai::Office::BreathPublisher.new(card: card.card_data, admin: @admin).call.post
    card.update_card!(Ai::Office::BreathPublisher.card_attrs_for(post))
    [ card.reload, post ]
  end

  test "the image picker lists the conversation's flyers and offers an upload" do
    flyer = flyer_card
    breath = breath_card
    get image_picker_admin_office_card_path(breath)
    assert_response :success
    assert_match "image_picker_#{breath.id}", response.body
    assert_match %(name="source_id" value="#{flyer.id}"), response.body
    assert_match 'accept="image/*"', response.body
  end

  test "choosing a flyer from the picker shows it on the breath, and it posts with it" do
    flyer = flyer_card
    breath = breath_card
    post attach_image_admin_office_card_path(breath), params: { source_id: flyer.id }, as: :turbo_stream
    assert_response :success
    assert_equal flyer.id, breath.reload.card_data["image_message_id"]
    assert_match "Change image", response.body
    assert_match "Remove image", response.body

    post post_breath_admin_office_card_path(breath), as: :turbo_stream
    assert_equal flyer.image.blob, Post.order(:id).last.images.first.blob
  end

  test "an image from another conversation can't be attached" do
    other = @admin.office_conversations.create!
    stranger = other.messages.new(role: :tool, content: "{}", payload: { "card" => { "kind" => "flyer" } })
    stranger.image.attach(io: StringIO.new(png_bytes), filename: "x.png", content_type: "image/png")
    stranger.save!
    breath = breath_card
    post attach_image_admin_office_card_path(breath), params: { source_id: stranger.id }, as: :turbo_stream
    assert_nil breath.reload.card_data["image_message_id"]
    assert_match "isn't in this conversation", breath.card_data["error"]
  end

  test "uploading an image attaches it to the breath; non-images and huge files are refused" do
    breath = breath_card
    post attach_image_admin_office_card_path(breath), params: { image: png_upload }, as: :turbo_stream
    assert breath.reload.image.attached?
    assert_equal breath.id, breath.card_data["image_message_id"]

    other = breath_card
    post attach_image_admin_office_card_path(other), params: { image: png_upload("notes.txt", content_type: "text/plain", bytes: "hello") }, as: :turbo_stream
    assert_not other.reload.image.attached?
    assert_match "isn't an image", other.card_data["error"]

    big = png_upload("big.png", bytes: "0" * (Post::IMAGE_MAX_BYTES + 1))
    post attach_image_admin_office_card_path(other), params: { image: big }, as: :turbo_stream
    assert_match "too large", other.reload.card_data["error"]
  end

  test "Remove image takes it off the breath" do
    flyer = flyer_card
    breath = breath_card("image_message_id" => flyer.id)
    post remove_image_admin_office_card_path(breath), as: :turbo_stream
    assert_nil breath.reload.card_data["image_message_id"]
    assert flyer.reload.image.attached?
  end

  test "the flyer's Add to a breath menu lists breaths newest first, with a new-breath option" do
    older = breath_card("title" => "Older one")
    newer = breath_card("title" => "Newer one", "status" => "posted", "post_id" => 1)
    flyer = flyer_card
    get breath_picker_admin_office_card_path(flyer)
    assert_response :success
    assert_operator response.body.index("Newer one"), :<, response.body.index("Older one")
    assert_match "New breath with this flyer", response.body
    assert_match "Add this image to your posted breath?", response.body
    assert_match %(value="#{older.id}"), response.body
    assert_match %(value="#{newer.id}"), response.body
  end

  test "Add to a breath on a posted breath (made before ids existed) puts the flyer on the live post" do
    breath, live = posted_breath
    keep = ActiveStorage::Blob.create_and_upload!(io: StringIO.new(png_bytes), filename: "keep.png", content_type: "image/png")
    live.images.attach(keep)
    flyer = flyer_card

    post add_to_breath_admin_office_card_path(flyer), params: { breath_id: breath.id }, as: :turbo_stream
    assert_response :success
    assert_match ActionView::RecordIdentifier.dom_id(breath), response.body

    assert_equal [ keep.id, flyer.image.blob.id ].sort, live.reload.images.map(&:blob_id).sort
    card = breath.reload.card_data
    assert_equal "posted", card["status"]
    assert_equal flyer.id, card["image_message_id"]
    assert card["updated_at"].present?
    assert_match "View breath", response.body

    # Removing it from the posted breath takes only the Office's image off the post.
    post remove_image_admin_office_card_path(breath), as: :turbo_stream
    perform_enqueued_jobs
    assert_equal [ keep.id ], live.reload.images.map(&:blob_id)
    assert flyer.reload.image.attached?
  end

  test "New breath with this flyer still starts a draft with the image" do
    flyer = flyer_card
    post use_in_breath_admin_office_card_path(flyer), as: :turbo_stream
    card = @conversation.messages.card.last
    assert_equal flyer.id, card.card_data["image_message_id"]
    assert_match "flyer #{flyer.id}", card.content
  end

  test "cards and replies carry their complete text for Copy" do
    body = "Paragraph one.\n\n" + ("A long line of the breath. " * 100) + "\n\nLast <words> & more."
    breath_card("title" => "The Hidden Years", "body" => body)
    reply = "## Plan\n\n- **one**\n- two <b>x</b>\n\n" + ("More text. " * 200)
    @conversation.messages.create!(role: :assistant, content: reply)
    broadcast = Broadcast.create!(sender: @admin, subject: "Thank you", body: "<p>#{'Thank you for being here. ' * 60}</p>")
    @conversation.messages.create!(role: :tool, content: "{}", payload: { "name" => "draft_email", "card" => { "kind" => "email", "broadcast_id" => broadcast.id } })
    @conversation.messages.create!(role: :tool, content: "{}", payload: { "name" => "draft_announcement", "card" => { "kind" => "announcement", "status" => "draft", "title" => "New", "kicker" => "Just shipped", "body" => "🎮 Games" } })

    get admin_office_conversation_path(@conversation)
    assert_response :success
    sources = Nokogiri::HTML5(response.body).css("template[data-office-copy-source]").map { |t| t.children.text }
    assert_includes sources, "The Hidden Years\n\n#{body}"
    assert_includes sources, reply
    assert_includes sources, "Thank you\n\n#{broadcast.body.to_plain_text.strip}"
    assert_includes sources, "Just shipped\n\nNew\n\n🎮 Games"
    assert_operator response.body.scan('data-action="office#copy"').size, :>=, 4
  end

  test "another admin can't use the pickers or attach to my cards" do
    other = create_member("other_admin_#{SecureRandom.hex(3)}", role: :admin)
    @conversation = other.office_conversations.create!
    breath = breath_card
    flyer = flyer_card
    get image_picker_admin_office_card_path(breath)
    assert_response :not_found
    sign_in @admin # a 404 doesn't carry the test session over
    post add_to_breath_admin_office_card_path(flyer), params: { breath_id: breath.id }
    assert_response :not_found
    assert_nil breath.reload.card_data["image_message_id"]
  end
end

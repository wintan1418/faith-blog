# frozen_string_literal: true

require "test_helper"

# Link previews for breaths without a photo: a card drawn for the breath
# (PostOgCard), linked with a version so previews refresh when the words
# change, and when the counts change no more than once a day.
class PostOgCardTest < ActionDispatch::IntegrationTest
  setup do
    ENV["AI_MODERATION_STUB"] = "1"
    @author = create_member("og_author", accent_color: "rose")
    @post = Post.create!(user: @author, title: "𝗪𝗵𝗼 𝗜𝘀 𝗮 𝗧𝗲𝗲𝗻𝗮𝗴𝗲𝗿? (𝟱)", content: "Listen before you lecture. 🙏",
                         status: :published, moderation_status: :approved, published_at: 1.hour.ago)
  end

  def og_image_url
    get post_path(@post)
    assert_response :success
    css_select(%(meta[property="og:image"])).first["content"]
  end

  test "the breath page points crawlers at an absolute card address that serves a JPEG" do
    url = og_image_url
    assert_match %r{\Ahttp://www\.example\.com/og/posts/#{@post.slug}\.jpg\?v=\w{10}-\d+\.\d+\z}, url
    assert_select %(meta[name="twitter:image"][content="#{url}"])
    assert_select %(meta[property="og:image:type"][content="image/jpeg"])

    get url
    assert_response :success
    assert_equal "image/jpeg", response.media_type
    assert_includes response.headers["Cache-Control"], "public"
    image = Vips::Image.new_from_buffer(response.body, "")
    assert_equal [ 1200, 630 ], [ image.width, image.height ]
  end

  test "the card is drawn once and reused" do
    get og_image_url
    assert @post.reload.og_card.attached?
    blob_id = @post.og_card.blob.id

    get og_image_url
    assert_response :success
    assert_equal blob_id, @post.reload.og_card.blob.id
    assert_equal 1, ActiveStorage::Attachment.where(record: @post, name: "og_card").count
  end

  test "a new title means a new card; new counts wait until the card is a day old" do
    first = og_image_url
    get first

    @post.update_columns(likes_count: 40)
    assert_equal first, og_image_url, "counts alone don't refresh a fresh card"

    @post.og_card.blob.update!(metadata: @post.og_card.blob.metadata.merge("generated_at" => 2.days.ago.iso8601))
    assert_not_equal first, og_image_url

    @post.update!(title: "A different title")
    assert_not_equal first, og_image_url
  end

  test "breaths with a photo, and breaths that aren't public, get no generated card" do
    @post.update_columns(status: Post.statuses[:draft])
    get post_og_image_path(@post, format: :jpg)
    assert_response :not_found

    @post.update_columns(status: Post.statuses[:published])
    @post.images.attach(io: Rails.root.join("public/icon.png").open, filename: "icon.png", content_type: "image/png")
    get post_path(@post)
    assert_no_match %r{/og/posts/}, css_select(%(meta[property="og:image"])).first["content"]
  end

  test "an anonymous breath's card shows no author" do
    secret = Post.create!(user: @author, title: "Please pray", content: "Hard week.", anonymous: true,
                          status: :published, moderation_status: :approved, published_at: 1.hour.ago)
    get post_og_image_path(secret, format: :jpg)
    assert_response :success
    card = PostOgCard.new(secret)
    assert_nil card.send(:author)
    assert_equal AccentPalette.for(nil), card.send(:palette)
  end

  test "styled Unicode letters become plain ones and emoji are dropped for the server font" do
    card = PostOgCard.new(@post)
    assert_equal "Who Is a Teenager? (5)", card.send(:title_text)
    assert_equal "Listen before you lecture.", card.send(:body_text)
  end
end

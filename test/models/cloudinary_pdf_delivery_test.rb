# frozen_string_literal: true

require "test_helper"

# PDFs in chats came back "HTTP 401" from Cloudinary; they now use a signed
# download link. Download links for photos force a download.
class CloudinaryPdfDeliveryTest < ActiveSupport::TestCase
  setup do
    ActiveStorage::Blob
    require "active_storage/service/cloudinary_service"
    CloudinaryPdfDelivery.apply!
    @service = ActiveStorage::Service::CloudinaryService.new(cloud_name: "demo", api_key: "123", api_secret: "abc",
                                                             folder: "brethreign/test")
  end

  test "a PDF gets a signed, expiring API download link" do
    url = @service.url("pdfkey", filename: ActiveStorage::Filename.new("Notes.pdf"), content_type: "application/pdf",
                                 disposition: "attachment; filename=Notes.pdf", expires_in: 5.minutes)
    assert_match %r{\Ahttps://api\.cloudinary\.com/v1_1/demo/image/download\?}, url
    assert_includes url, "public_id=brethreign%2Ftest%2Fpdfkey"
    assert_includes url, "format=pdf"
    assert_includes url, "attachment=true"
    assert_includes url, "signature="
    assert_includes url, "expires_at="
  end

  test "a photo download link saves the file; a photo shown inline doesn't" do
    download = @service.url("img", filename: ActiveStorage::Filename.new("a.jpg"), content_type: "image/jpeg", disposition: "attachment")
    inline = @service.url("img", filename: ActiveStorage::Filename.new("a.jpg"), content_type: "image/jpeg", disposition: "inline")
    assert_includes download, "/fl_attachment/"
    assert_not_includes inline, "fl_attachment"
  end

  test "Word documents keep their normal link" do
    url = @service.url("doc", filename: ActiveStorage::Filename.new("a.docx"),
                              content_type: "application/vnd.openxmlformats-officedocument.wordprocessingml.document", disposition: "attachment")
    assert_match %r{\Ahttps://res\.cloudinary\.com/demo/raw/upload/}, url
  end
end

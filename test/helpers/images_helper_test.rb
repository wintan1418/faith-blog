# frozen_string_literal: true

require "test_helper"
require "minitest/mock"
require "active_storage/service/cloudinary_service"

class ImagesHelperTest < ActionView::TestCase
  PNG = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")

  def blob
    @blob ||= ActiveStorage::Blob.create_and_upload!(io: StringIO.new(PNG), filename: "face.png", content_type: "image/png")
  end

  test "Cloudinary images get a resized, auto-compressed CDN link" do
    cloudinary = ActiveStorage::Service::CloudinaryService.new(cloud_name: "demo", secure: true)
    blob.stub(:service, cloudinary) do
      url = resized_image_src(blob, width: 96, height: 96, crop: "fill", gravity: "face")
      assert_match %r{\Ahttps://res\.cloudinary\.com/demo/image/upload/}, url
      assert_includes url, "w_96"
      assert_includes url, "h_96"
      assert_includes url, "c_fill"
      assert_includes url, "f_auto"
      assert_includes url, "q_auto"
    end
  end

  test "anything not on Cloudinary falls back to the original" do
    assert_same blob, resized_image_src(blob, width: 96, crop: "fill")
  end
end

require "test_helper"

class ResharesControllerTest < ActionDispatch::IntegrationTest
  test "should get create" do
    get reshares_create_url
    assert_response :success
  end

  test "should get destroy" do
    get reshares_destroy_url
    assert_response :success
  end
end

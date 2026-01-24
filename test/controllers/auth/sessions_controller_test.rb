require "test_helper"

class Auth::SessionsControllerTest < ActionDispatch::IntegrationTest
  test "should get create" do
    get auth_sessions_create_url
    assert_response :success
  end
end

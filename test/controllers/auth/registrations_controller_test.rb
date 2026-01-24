require "test_helper"

class Auth::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "should get create" do
    get auth_registrations_create_url
    assert_response :success
  end
end

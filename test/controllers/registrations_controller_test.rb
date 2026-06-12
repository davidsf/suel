require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  test "signup creates the user and signs them in" do
    assert_difference "User.count", 1 do
      post registration_path, params: {
        user: { email_address: "nuevo@example.com", password: "secreto1", password_confirmation: "secreto1" }
      }
    end
    assert_redirected_to root_url
    assert cookies[:session_id].present?, "should be signed in after signup"
  end

  test "duplicate email is rejected" do
    assert_no_difference "User.count" do
      post registration_path, params: {
        user: { email_address: users(:one).email_address, password: "secreto1", password_confirmation: "secreto1" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "password confirmation mismatch is rejected" do
    assert_no_difference "User.count" do
      post registration_path, params: {
        user: { email_address: "otro@example.com", password: "secreto1", password_confirmation: "distinta" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "short password is rejected" do
    assert_no_difference "User.count" do
      post registration_path, params: {
        user: { email_address: "otro@example.com", password: "abc", password_confirmation: "abc" }
      }
    end
    assert_response :unprocessable_entity
  end
end

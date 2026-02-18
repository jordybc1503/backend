require "test_helper"

class Api::V1::ConversationReportEndpointTest < ActionDispatch::IntegrationTest
  test "downloads report with only interviewer and user messages" do
    user = User.create!(email: "report-endpoint@example.com", password: "password123")
    conversation = user.conversations.create!(title: "System design")
    token = JsonWebToken.encode(user_id: user.id)

    conversation.messages.create!(user: user, role: "interviewer", content: "Design a URL shortener.")
    conversation.messages.create!(user: user, role: "assistant", content: "Think about scale first.")
    conversation.messages.create!(user: user, role: "user", content: "I would start with API requirements.")

    get "/api/v1/conversations/#{conversation.id}/report",
        headers: { "Authorization" => "Bearer #{token}" }

    assert_response :success
    assert_equal "text/plain", response.media_type
    assert_match(/attachment; filename=/, response.headers["Content-Disposition"])
    assert_includes response.body, "Design a URL shortener."
    assert_includes response.body, "I would start with API requirements."
    assert_not_includes response.body, "Think about scale first."
  end

  test "returns unauthorized without token" do
    user = User.create!(email: "report-no-token@example.com", password: "password123")
    conversation = user.conversations.create!(title: "Unauthorized report")

    get "/api/v1/conversations/#{conversation.id}/report"

    assert_response :unauthorized
  end
end

require "test_helper"

class Api::V1::CaptionsModesAndUpsertTest < ActionDispatch::IntegrationTest
  def auth_headers_for(user)
    token = JsonWebToken.encode(user_id: user.id)
    { "Authorization" => "Bearer #{token}" }
  end

  test "manual_last_interviewer mode skips automatic assistant response" do
    user = User.create!(email: "captions-manual@example.com", password: "password123")
    conversation = user.conversations.create!(title: "Captions manual mode")

    post "/api/v1/conversations/#{conversation.id}/captions",
         params: {
           text: "How would you solve this architecture?",
           speaker: "Interviewer",
           platform: "meet",
           response_mode: "manual_last_interviewer"
         },
         headers: auth_headers_for(user)

    assert_response :created
    payload = JSON.parse(response.body)
    assert_nil payload["assistant_message"]
    assert_equal 1, conversation.messages.where(role: "interviewer").count
    assert_equal 0, conversation.messages.where(role: "assistant").count
  end

  test "incremental caption updates are merged into a single message" do
    user = User.create!(email: "captions-upsert@example.com", password: "password123")
    conversation = user.conversations.create!(title: "Captions upsert")
    headers = auth_headers_for(user)

    post "/api/v1/conversations/#{conversation.id}/captions",
         params: {
           text: "I worked with",
           speaker: "You",
           platform: "meet",
           response_mode: "manual_last_interviewer"
         },
         headers: headers
    assert_response :created

    first_message = conversation.messages.where(role: "user").order(created_at: :desc).first
    first_message.update_column(:created_at, 40.seconds.ago)

    post "/api/v1/conversations/#{conversation.id}/captions",
         params: {
           text: "I worked with Ruby on Rails for backend systems",
           speaker: "You",
           platform: "meet",
           response_mode: "manual_last_interviewer"
         },
         headers: headers

    assert_response :created
    payload = JSON.parse(response.body)
    updated_message = payload["caption_message"]

    assert_equal first_message.id, updated_message["id"]
    assert_equal 1, conversation.messages.where(role: "user").count
    assert_includes updated_message["content"], "Ruby on Rails"
  end
end

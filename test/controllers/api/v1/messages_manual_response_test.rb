require "test_helper"

class Api::V1::MessagesManualResponseTest < ActionDispatch::IntegrationTest
  def auth_headers_for(user)
    token = JsonWebToken.encode(user_id: user.id)
    { "Authorization" => "Bearer #{token}" }
  end

  def with_stubbed_chat_completion(response_text)
    original_new = Ai::ChatCompletionService.method(:new)
    Ai::ChatCompletionService.define_singleton_method(:new) do |**_kwargs|
      Struct.new(:response_text) do
        def call
          response_text
        end
      end.new(response_text)
    end

    yield
  ensure
    Ai::ChatCompletionService.define_singleton_method(:new, original_new)
  end

  test "respond_last_interviewer creates assistant suggestion from last interviewer message" do
    user = User.create!(email: "manual-trigger@example.com", password: "password123")
    conversation = user.conversations.create!(title: "Manual trigger")
    conversation.messages.create!(user: user, role: "interviewer", content: "How did you approach the project?")

    with_stubbed_chat_completion("You can answer with your approach.") do
      post "/api/v1/conversations/#{conversation.id}/messages/respond_last_interviewer",
           headers: auth_headers_for(user)
    end

    assert_response :ok
    payload = JSON.parse(response.body)
    assistant_message = payload["assistant_message"]

    assert_equal false, payload["skipped"]
    assert_equal "assistant", assistant_message["role"]
    assert_equal "suggestion", assistant_message["status"]
    assert_equal "You can answer with your approach.", assistant_message["content"]
  end

  test "respond_last_interviewer creates a new suggestion even when one already exists" do
    user = User.create!(email: "manual-trigger-skipped@example.com", password: "password123")
    conversation = user.conversations.create!(title: "Manual trigger skipped")
    interviewer_message = conversation.messages.create!(
      user: user,
      role: "interviewer",
      content: "Tell me your biggest challenge."
    )
    conversation.messages.create!(
      user: user,
      role: "assistant",
      content: "Use STAR and mention measurable impact.",
      status: "suggestion",
      created_at: interviewer_message.created_at - 1.second
    )

    with_stubbed_chat_completion("Here is an alternative concise answer.") do
      post "/api/v1/conversations/#{conversation.id}/messages/respond_last_interviewer",
           headers: auth_headers_for(user)
    end

    assert_response :ok
    payload = JSON.parse(response.body)
    assert_equal false, payload["skipped"]

    latest_assistant = conversation.messages.where(role: "assistant").order(created_at: :desc).first
    assert_equal "Here is an alternative concise answer.", latest_assistant.content
    assert_equal 2, conversation.messages.where(role: "assistant").count
  end

  test "respond_last_interviewer returns error when there is no interviewer message" do
    user = User.create!(email: "manual-trigger-empty@example.com", password: "password123")
    conversation = user.conversations.create!(title: "No interviewer")
    conversation.messages.create!(user: user, role: "user", content: "Candidate answer only")

    post "/api/v1/conversations/#{conversation.id}/messages/respond_last_interviewer",
         headers: auth_headers_for(user)

    assert_response :unprocessable_entity
    payload = JSON.parse(response.body)
    assert_includes payload["error"], "No hay mensajes del interviewer"
  end
end

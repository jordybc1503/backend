require "test_helper"

class Conversations::MessagesReportServiceTest < ActiveSupport::TestCase
  test "builds report including only interviewer and user messages" do
    user = User.create!(email: "report-service@example.com", password: "password123")
    conversation = user.conversations.create!(title: "Mock interview")

    interviewer_message = conversation.messages.create!(
      user: user,
      role: "interviewer",
      content: "Tell me about yourself."
    )
    assistant_message = conversation.messages.create!(
      user: user,
      role: "assistant",
      content: "You can start with your background."
    )
    user_message = conversation.messages.create!(
      user: user,
      role: "user",
      content: "I am a backend engineer with 5 years of experience."
    )

    interviewer_message.update_column(:created_at, Time.utc(2026, 1, 1, 10, 0, 0))
    assistant_message.update_column(:created_at, Time.utc(2026, 1, 1, 10, 1, 0))
    user_message.update_column(:created_at, Time.utc(2026, 1, 1, 10, 2, 0))

    report = Conversations::MessagesReportService.new(conversation: conversation).call
    content = report[:content]

    assert_match(/^reporte-mock-interview-\d{8}-\d{6}\.txt$/, report[:filename])
    assert_includes content, "1. [2026-01-01T10:00:00Z] Interviewer"
    assert_includes content, "2. [2026-01-01T10:02:00Z] User"
    assert_includes content, "Tell me about yourself."
    assert_includes content, "I am a backend engineer with 5 years of experience."
    assert_not_includes content, "You can start with your background."
  end

  test "adds empty-state line when no interviewer/user messages exist" do
    user = User.create!(email: "report-empty@example.com", password: "password123")
    conversation = user.conversations.create!(title: "No reportable messages")
    conversation.messages.create!(
      user: user,
      role: "assistant",
      content: "No candidate or interviewer turns yet."
    )

    report = Conversations::MessagesReportService.new(conversation: conversation).call

    assert_includes report[:content], "No messages found for roles interviewer/user."
  end
end

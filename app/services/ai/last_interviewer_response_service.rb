module Ai
  class LastInterviewerResponseService
    class Error < StandardError; end
    class NoInterviewerMessageError < Error; end

    def initialize(conversation:, user:)
      @conversation = conversation
      @user = user
    end

    def call
      interviewer_message = latest_interviewer_message
      raise NoInterviewerMessageError, "No hay mensajes del interviewer para responder." if interviewer_message.nil?

      assistant_content = Ai::ChatCompletionService.new(conversation: conversation).call
      assistant_message = conversation.messages.create!(
        user: user,
        role: "assistant",
        content: assistant_content,
        status: "suggestion"
      )

      {
        assistant_message: assistant_message,
        interviewer_message: interviewer_message,
        skipped: false
      }
    rescue Ai::ChatCompletionService::Error => e
      raise Error, e.message
    end

    private

    attr_reader :conversation, :user

    def latest_interviewer_message
      conversation.messages.where(role: "interviewer").order(created_at: :desc).first
    end
  end
end

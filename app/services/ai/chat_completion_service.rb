module Ai
  class ChatCompletionService
    class Error < StandardError; end

    DEFAULT_MODEL = ENV.fetch("AI_DEFAULT_MODEL", "gpt-5-nano").freeze
    RECENT_WINDOW_SIZE = ENV.fetch("AI_RECENT_WINDOW_SIZE", "18").to_i
    MAX_WINDOW_WITHOUT_SUMMARY = ENV.fetch("AI_MAX_WINDOW_WITHOUT_SUMMARY", "60").to_i
    DEFAULT_SYSTEM_PROMPT = ENV.fetch(
      "AI_DEFAULT_SYSTEM_PROMPT",
      "You are a real-time interview assistant. Messages may be labeled as Interviewer or Candidate. " \
      "Respond with a concise suggested answer the candidate can say next."
    ).freeze

    def initialize(conversation:, api_key: nil)
      @conversation = conversation
      @api_key = api_key.presence || conversation.ai_api_key.presence || ENV["AI_API_KEY"]
      @model = conversation.ai_model.presence || DEFAULT_MODEL
      @system_prompt = conversation.ai_system_prompt.presence || DEFAULT_SYSTEM_PROMPT
    end

    def call
      raise Error, "Missing AI API key" if @api_key.blank?

      client = Ai::HttpClient.new(api_key: @api_key)
      response_payload = client.chat(messages: build_messages, model: @model)
      content = extract_content(response_payload)

      raise Error, "AI returned an empty response" if content.blank?

      content
    rescue Ai::HttpClient::Error => e
      raise Error, e.message
    end

    private

    attr_reader :conversation

    def build_messages
      base_messages = []
      base_messages << { role: "system", content: @system_prompt } if @system_prompt.present?
      summary_message = summary_system_message
      base_messages << summary_message if summary_message

      history_messages = recent_messages.filter_map do |message|
        next if message.role.blank? || message.content.blank?

        normalize_message(message)
      end

      base_messages + history_messages
    end

    def summary_system_message
      return nil if conversation.ai_summary.blank?

      {
        role: "system",
        content: "Conversation summary so far:\n#{conversation.ai_summary}"
      }
    end

    def recent_messages
      conversation.messages.order(created_at: :desc).limit(message_window_size).to_a.reverse
    end

    def message_window_size
      size = recent_window_size
      return size if conversation.ai_summary.present?

      [size * 3, max_window_without_summary].min
    end

    def recent_window_size
      RECENT_WINDOW_SIZE.positive? ? RECENT_WINDOW_SIZE : 18
    end

    def max_window_without_summary
      MAX_WINDOW_WITHOUT_SUMMARY.positive? ? MAX_WINDOW_WITHOUT_SUMMARY : 60
    end

    def normalize_message(message)
      role = message.role.to_s
      content = message.content.to_s

      case role
      when "assistant"
        { role: "assistant", content: }
      when "system"
        { role: "system", content: }
      when "interviewer"
        { role: "user", content: "Interviewer: #{content}" }
      when "user"
        { role: "user", content: "Candidate: #{content}" }
      else
        { role: "user", content: }
      end
    end

    def extract_content(payload)
      payload.dig("choices", 0, "message", "content")
    end
  end
end

module Ai
  class ConversationSummaryService
    class Error < StandardError; end

    SUMMARY_TRIGGER_COUNT = ENV.fetch("AI_SUMMARY_TRIGGER_COUNT", "12").to_i
    MAX_MESSAGES_FOR_SUMMARY = ENV.fetch("AI_SUMMARY_MAX_MESSAGES", "40").to_i
    DEFAULT_SUMMARY_MODEL = ENV["AI_SUMMARY_MODEL"].presence

    def initialize(conversation:, api_key: nil)
      @conversation = conversation
      @api_key = api_key.presence || conversation.ai_api_key.presence || ENV["AI_API_KEY"]
      @model = DEFAULT_SUMMARY_MODEL || conversation.ai_model.presence || ChatCompletionService::DEFAULT_MODEL
    end

    def call
      return if @api_key.blank?

      messages = messages_since_last_summary
      return if messages.empty?
      return unless should_update_summary?(messages)

      summary_text = generate_summary(messages)
      update_summary!(summary_text, messages.last.id)
    rescue Ai::HttpClient::Error => e
      raise Error, e.message
    end

    private

    attr_reader :conversation

    def messages_since_last_summary
      scope = conversation.messages.order(:created_at)

      if conversation.ai_summary_updated_at.present?
        scope = scope.where("updated_at > ?", conversation.ai_summary_updated_at)
      elsif conversation.ai_summary_message_id.present?
        scope = scope.where("id > ?", conversation.ai_summary_message_id)
      end

      scope.limit(max_messages_for_summary).to_a
    end

    def should_update_summary?(messages)
      return true if conversation.ai_summary.blank?

      messages.size >= summary_trigger_count
    end

    def generate_summary(messages)
      client = Ai::HttpClient.new(api_key: @api_key)
      payload = client.chat(messages: summary_messages(messages), model: @model)
      extract_content(payload)
    end

    def summary_messages(messages)
      base_messages = [
        {
          role: "system",
          content:
            "You maintain a compact running summary of an interview conversation. " \
            "Preserve important requirements, decisions, interviewer questions, and strong candidate answers. " \
            "Keep it under 180 words in clear bullet points."
        }
      ]

      if conversation.ai_summary.present?
        base_messages << {
          role: "system",
          content: "Existing summary:\n#{conversation.ai_summary}"
        }
      end

      base_messages << {
        role: "user",
        content: build_summary_input(messages)
      }

      base_messages
    end

    def build_summary_input(messages)
      lines = messages.map.with_index(1) do |message, index|
        "#{index}. #{label_for(message)}: #{message.content.to_s.strip}"
      end.join("\n")

      <<~TEXT
        Update the running summary with the following new conversation turns.
        If the new turns contradict the previous summary, prefer the new turns.

        New turns:
        #{lines}
      TEXT
    end

    def label_for(message)
      case message.role.to_s
      when "assistant"
        "Assistant"
      when "interviewer"
        "Interviewer"
      when "user"
        "Candidate"
      else
        message.role.to_s.titleize.presence || "Message"
      end
    end

    def update_summary!(summary_text, last_message_id)
      return if summary_text.blank?

      conversation.update!(
        ai_summary: summary_text,
        ai_summary_message_id: last_message_id,
        ai_summary_updated_at: Time.current
      )
    end

    def summary_trigger_count
      SUMMARY_TRIGGER_COUNT.positive? ? SUMMARY_TRIGGER_COUNT : 12
    end

    def max_messages_for_summary
      MAX_MESSAGES_FOR_SUMMARY.positive? ? MAX_MESSAGES_FOR_SUMMARY : 40
    end

    def extract_content(payload)
      payload.dig("choices", 0, "message", "content")
    end
  end
end

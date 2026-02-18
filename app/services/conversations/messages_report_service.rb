module Conversations
  class MessagesReportService
    INCLUDED_ROLES = %w[interviewer user].freeze

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      {
        filename: build_filename,
        content: build_content
      }
    end

    private

    attr_reader :conversation

    def build_filename
      conversation_slug = conversation.title.to_s.parameterize.presence || "conversation-#{conversation.id}"
      timestamp = Time.current.strftime("%Y%m%d-%H%M%S")
      "reporte-#{conversation_slug}-#{timestamp}.txt"
    end

    def build_content
      lines = []
      lines << "Conversation ID: #{conversation.id}"
      lines << "Title: #{conversation.title.presence || "Sin titulo"}"
      lines << "Generated At (UTC): #{Time.current.utc.iso8601}"
      lines << ""
      lines << "Messages:"

      if filtered_messages.empty?
        lines << "No messages found for roles interviewer/user."
      else
        filtered_messages.each_with_index do |message, index|
          lines << format_message(index + 1, message)
        end
      end

      "#{lines.join("\n").strip}\n"
    end

    def filtered_messages
      @filtered_messages ||= conversation.messages.where(role: INCLUDED_ROLES).order(:created_at)
    end

    def format_message(index, message)
      timestamp = message.created_at&.utc&.iso8601 || "unknown-time"
      role_label = message.role.to_s == "interviewer" ? "Interviewer" : "User"
      content = message.content.to_s.strip

      <<~TEXT.chomp
        #{index}. [#{timestamp}] #{role_label}
        #{content}
      TEXT
    end
  end
end

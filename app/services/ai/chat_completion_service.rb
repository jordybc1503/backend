require "json"
require "net/http"
require "uri"

module Ai
  class ChatCompletionService
    class Error < StandardError; end

    DEFAULT_BASE_URL = ENV.fetch("AI_BASE_URL", "https://api.openai.com/v1").freeze
    DEFAULT_MODEL = ENV.fetch("AI_DEFAULT_MODEL", "gpt-4o-mini").freeze
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

      response_payload = perform_request
      content = extract_content(response_payload)

      raise Error, "AI returned an empty response" if content.blank?

      content
    end

    private

    attr_reader :conversation

    def perform_request
      uri = URI.parse("#{DEFAULT_BASE_URL}/chat/completions")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"
      request.body = build_request_body.to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "AI request failed with status #{response.code}"
      end

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise Error, "Unable to parse AI response: #{e.message}"
    end

    def build_request_body
      {
        model: @model,
        messages: build_messages
      }
    end

    def build_messages
      base_messages = []
      base_messages << { role: "system", content: @system_prompt } if @system_prompt.present?

      history_messages = conversation.messages.order(:created_at).filter_map do |message|
        next if message.role.blank? || message.content.blank?

        normalize_message(message)
      end

      base_messages + history_messages
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

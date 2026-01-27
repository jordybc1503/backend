require "json"
require "net/http"
require "uri"

module Ai
  class HttpClient
    class Error < StandardError; end

    DEFAULT_BASE_URL = ENV.fetch("AI_BASE_URL", "https://api.openai.com/v1").freeze

    def initialize(api_key:, base_url: DEFAULT_BASE_URL)
      @api_key = api_key.to_s
      @base_url = base_url
    end

    def chat(messages:, model:, temperature: nil)
      raise Error, "Missing AI API key" if @api_key.blank?

      uri = URI.parse("#{@base_url}/chat/completions")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"
      request.body = build_body(messages:, model:, temperature:).to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "AI request failed with status #{response.code}"
      end

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise Error, "Unable to parse AI response: #{e.message}"
    end

    private

    def build_body(messages:, model:, temperature:)
      body = {
        model: model,
        messages: messages
      }

      body[:temperature] = temperature if temperature
      body
    end
  end
end

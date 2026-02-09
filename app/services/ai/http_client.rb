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

    def chat(messages:, model:, temperature: nil, stream: false, &block)
      raise Error, "Missing AI API key" if @api_key.blank?

      if stream
        chat_stream(messages:, model:, temperature:, &block)
      else
        chat_non_stream(messages:, model:, temperature:)
      end
    end

    private

    def chat_non_stream(messages:, model:, temperature:)
      uri = URI.parse("#{@base_url}/chat/completions")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"
      request.body = build_body(messages:, model:, temperature:, stream: false).to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise Error, "AI request failed with status #{response.code}"
      end

      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise Error, "Unable to parse AI response: #{e.message}"
    end

    def chat_stream(messages:, model:, temperature:, &block)
      uri = URI.parse("#{@base_url}/chat/completions")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.read_timeout = 60

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"
      request.body = build_body(messages:, model:, temperature:, stream: true).to_json

      http.request(request) do |response|
        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "AI stream request failed with status #{response.code}"
        end

        buffer = ""
        response.read_body do |chunk|
          # Add chunk to buffer
          buffer += chunk

          # Process complete lines (split on any newline, keeping empty lines)
          while buffer.include?("\n")
            line, buffer = buffer.split("\n", 2)
            line = line.strip

            # Skip empty lines
            next if line.empty?

            # SSE format: "data: {...}" or just the event marker "data: [DONE]"
            if line.start_with?("data: ")
              data = line[6..].strip  # Remove "data: " prefix
              next if data == "[DONE]"

              begin
                parsed = JSON.parse(data)
                delta = parsed.dig("choices", 0, "delta", "content")
                block.call(delta) if delta && block
              rescue JSON::ParserError => e
                Rails.logger.warn("[ai-stream] Failed to parse chunk: #{data[0..100]}")
              end
            end
          end
        end
      end
    rescue => e
      raise Error, "Stream error: #{e.message}"
    end

    def build_body(messages:, model:, temperature:, stream: false)
      body = {
        model: model,
        messages: messages,
        stream: stream
      }

      body[:temperature] = temperature if temperature
      body
    end
  end
end
